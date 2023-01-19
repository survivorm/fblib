#
#
#       FictionBook v2 manipulation library written in Nim
#        (c) Copyright 2023 Michael Voronin
#
#    Provided "AS IS". Absolutely no warrancy

import sets
import re
import os
import sugar
import typetraits
import xmlparser, xmltree, parsexml
import fblib/xmllib
import streams
import macros, strutils, sequtils

## A simple FictionBook v2 manipulation library.
## Can load, save, append/merge fictionbook files. In beta development
##
runnableExamples:
    import os
    echo getCurrentDir()
    # Example loading
    var m = newMetadata(file="./tests/data/test.fb2")
    var b: Book = newBook(metadata=m)
    discard b.load()
    # Example on saving according to book author
    discard b.newMetadata() # filename is chosen from book name/author
    discard b.save()
## See also:
## * `appendFiles proc <#appendFiles,Book,seq[string]>`_ to add chapters from
## *subbooks* to *book*
## * `appendFiles proc <#appendFiles,Book,string>`_ to add chapters from all fb2
## files in *directory* to *book*
## * `merge proc <#merge,seq[string]>`_ to merge chapters from all *files*,
## using sequence order of files
## * `merge proc <#merge,string>`_ to merge chapters from all fb2 files in *directory*.
## Files are merged alphabetically, description is taken fro first file

type
    Author* = ref object
        ## Object representation of XML path /description/title-info/author
        ##
        ## Use `newAuthor proc <#newAuthor,string,string,string,string,string,string>`_
        ## for creating a new *text* author. All params are optional.
        ##
        ## See also:
        ## * `newDocumentAuthor proc <#newDocumentAuthor,string,string,string>`_ for fb2 *document* author
        firstName*: string
        middleName*: string
        lastName*: string
        nickname*: string
        homePage*: string
        email*: string
    Translator* = ref object
        ## Object representation of XML path /description/title-info/translator
        ##
        ## Use `newTranslator proc <#newTranslator,string,string,string>`_
        ## for creating a new translator. All params are optional
        firstName*: string
        middleName*: string
        lastName*: string
    TTitleInfo* = ref object
        ## Object representation of XML path /description/title-info
        ##
        ## Use `newTTitleInfo proc <#newTTitleInfo,seq[string],Author,string,string,seq[string],string,string,string,string,Translator>`_
        ## for creating a info for this certain *text*. All params are optional
        ##
        ## See also:
        ## * `newDDocumentInfo proc <#newDDocumentInfo,DocumentAuthor,string,string,string,string,string,string,string>`_ for fb2 *document* info
        ## * `newPPublishInfo proc <#newPPublishInfo,string,string,string,int,string>`_ for *published* document info
        ## * `newAuthor proc <#newAuthor,string,string,string,string,string,string>`_ for book *text* author
        genres*: seq[string]
        author*: Author
        bookTitle*:string
        annotation*: string
        keywords*: seq[string]
        date*: string
        coverpage*: string
        lang*: string
        srcLang*: string
        translator*: Translator
    DocumentAuthor* = ref object
        ## Object representation of XML path /description/document-info/author
        ##
        ## Use `newDocumentAuthor proc <#newDocumentAuthor,string,string,string>`_
        ## for creating a new *document* author. All params are optional
        ##
        ## See also:
        ## * `newAuthor proc <#newAuthor,string,string,string,string,string,string>`_ for book *text* author
        firstName*: string
        middleName*: string
        lastName*: string
    DDocumentInfo* = ref object
        ## Object representation of XML path /description/document-info.
        ## 
        ## This is this fb2 document information - who formed it,
        ## in which program, etc.
        ##
        ## Use `newDDocumentInfo proc <#newDDocumentInfo,DocumentAuthor,string,string,string,string,string,string,string>`_
        ## for creating a new *document* info. All params are optional
        ##
        ## See also:
        ## * `newTTitleInfo proc <#newTTitleInfo,seq[string],Author,string,string,seq[string],string,string,string,string,Translator>`_ for book *text* info
        ## * `newPPublishInfo proc <#newPPublishInfo,string,string,string,int,string>`_ for *published* document info
        ## * `newDocumentAuthor proc <#newDocumentAuthor,string,string,string>`_ for fb2 *document* author
        author*: DocumentAuthor
        programUsed*: string
        date*: string
        srcUrl*: string
        srcOcr*: string
        id*: string
        version*: string
        history*: string
    PPublishInfo* = ref object
        ## Object representation of XML path /description/publish-info
        ##
        ## Paper book info, on which this electronic book is based
        ##
        ## Use `newPPublishInfo proc <#newPPublishInfo,string,string,string,int,string>`_
        ## for creating a new *published* document info. All params are optional
        ##
        ## See also:
        ## * `newTTitleInfo proc <#newTTitleInfo,seq[string],Author,string,string,seq[string],string,string,string,string,Translator>`_ for book *text* info
        ## * `newDDocumentInfo proc <#newDDocumentInfo,DocumentAuthor,string,string,string,string,string,string,string>`_ for fb2 *document* info
        bookName*: string
        publisher*: string
        city*: string
        year*: int
        isbn*: string
    Description* = ref object
        ## Object representation of XML path /description
        ##
        ## Whole book description, annotation, author, translator, document
        ## author, publish info and etc
        ## Use `newDescription proc <#newDescription,TTitleInfo,DDocumentInfo,PPublishInfo>`_
        ## for creating a new document info. All params are optional
        ##
        ## See also:
        ## * `newTTitleInfo proc <#newTTitleInfo,seq[string],Author,string,string,seq[string],string,string,string,string,Translator>`_ for book *text* info
        ## * `newDDocumentInfo proc <#newDDocumentInfo,DocumentAuthor,string,string,string,string,string,string,string>`_ for fb2 *document* info
        ## * `newPPublishInfo proc <#newPPublishInfo,string,string,string,int,string>`_ for *published* document info
        titleInfo*: TTitleInfo
        documentInfo*: DDocumentInfo
        publishInfo*: PPublishInfo
    CKind* = enum tSection, tText
    Image* = ref object
        ## Binary (image)
        ##
        ## To add an Image, use 
        ## `newImage proc <#newImage,string,string>`_ 
        name: string
        data: string
    Section* = ref object
        ## Object representation of XML path /body/../section.
        ## 
        ## In essence - it's a chapter/part of the document.
        ## It may be of different kind - either text or parent to other sections
        ##
        ## To create chapter unbound to any book you may use 
        ## * `newSection proc <#newSection,CKind,string,Image,seq[string],string>`_ (to create empty section of chosen kind)
        ## * `newSection proc <#newSection,string,string,Image,seq[string],string,set[ParseFlags]>`_ (to create text section)
        ## * `newSection proc <#newSection,seq[Section],string,Image,seq[string],string>`_ (to create parent to other subsections section)
        ##
        ## See also:
        ## * `addChapter proc <#addChapter,Book,Section>`_ to add existing chapter to book
        ## * `addChapter proc <#addChapter,Book,string,string,Image,seq[string],string,set[ParseFlags]>`_ to add new text chapter to book
        ## * `appendChapter proc <#appendChapter,Section,string>`_ to append text to existing chapter
        title*: string
        image*: Image
        epigraph*: seq[string]
        annotation*: string
        case kind*: CKind
        of tSection:
            sections*: seq[Section]
        of tText:
            text*: string 
    ParseFlags* = enum
        ## Flags for book processing
        pAuto, pPlain, pSplit, pNoParse
    CleanFlags* = enum
        ## flags for string cleaning (e.g. Author title)
        cStrip, cNoSpec, cSquashSymbols
    Metadata* = ref object
        ## metadata object for book save/load/other manipulations
        ## 
        ## * Flags are used for loading from file/adding new chapters.
        ## * File is book filename.
        ## * If filename is omitted, fileTemplate is used to generate filename
        ## based on the name of the book, name of author and chapters count
        ##
        ## To create metadata
        ## * use `newMetadata proc <#newMetadata,set[ParseFlags],string,string>`_
        ## * use `newMetadata proc <#newMetadata,Book,set[ParseFlags],string,string>`_ to create and add to an existing book
        ##
        ## See also:
        ## * `newBook proc <#newBook,Description,seq[Section],Metadata>`_ to create book and add metadata object to it

        flags: set[ParseFlags]
        file: string
        fileTemplate: string
    Book* = ref object
        ## Whole book object representation.
        ##
        ## Use `newBook proc <#newBook,Description,seq[Section],Metadata>`_
        ## for creating a new book. All params are optional
        ##
        ## See also:
        ## * `newDescription proc <#newDescription,TTitleInfo,DDocumentInfo,PPublishInfo>`_ - to create book's description
        ## * `newSection proc <#newSection,CKind,string,Image,seq[string],string>`_ to create empty section of chosen kind
        ## * `newSection proc <#newSection,string,string,Image,seq[string],string,set[ParseFlags]>`_ to create text section
        ## * `newSection proc <#newSection,seq[Section],string,Image,seq[string],string>`_ to create parent to other subsections section
        ## * `newImage proc <#newImage,string,string>`_ to create new binary (image)
        ## * `newMetadata proc <#newMetadata,set[ParseFlags],string,string>`_ - to create unbound metadata
        ## * `newMetadata proc <#newMetadata,Book,set[ParseFlags],string,string>`_ to create metadata and add to an existing book
        description*: Description
        body*: seq[Section]
        binary: seq[Image]
        metadata: Metadata

const textSectionTags = @["p", "br", "image", "empty-line", "poem", "subtitle", "cite", "section"]
const sectionTags = textSectionTags & @["title", "annotation", "epigraph"]
const mappedTags = @["br", "article", "figure", "pre", "div", "h1", "h2", "h3"]
const textMappedTags = mappedTags & @["title"]
const tagMap = @["empty-line", "poem", "poem", "poem", "p", "subtitle", "subtitle", "subtitle"]
const textTagMap = tagMap & @["subtitle"]
const pTags = ["style", "strong", "note", "image"]
const titleTags = ["p", "empty-line"]
const xmlParseOpts = {allowUnquotedAttribs, allowEmptyAttribs}

macro getField(obj: ref object, fld: string): untyped =
  ## Turn ``obj.getField("fld")`` into ``obj.fld``.
  newDotExpr(obj, newIdentNode(fld.strVal))

proc filterSection(xmlSection: var XmlNode): XmlNode =
    ## Filter xml Section text of disallowed tags
    var section = xmlSection
    discard section.restrictTags(
        allow = sectionTags, mapFrom = mappedTags, mapTo = tagMap
    )
    for paragraph in section.mitems:
        if paragraph.tag == "p":
            discard paragraph.restrictTags(allow = pTags)
        elif paragraph.tag in ["section", "annotation"]:
            discard
        if paragraph.tag == "title":
            discard paragraph.restrictTags(allow = titleTags)
        else:
            discard paragraph.restrictTags(allow = [])
    return xmlSection


proc getXmlObjName(name: string): string = 
    var start = name.find(re"[A-Z]", 1)
    if start == -1:
        start = 0
    var oName = (name[start] & name[start + 1 .. ^1].replacef(
        re"([A-Z])", "-$1")).toLowerAscii
    return oName


proc newImage* (name, data: string = ""): Image =
    ## Create binary - image
    return Image(
        name: name,
        data: data
    )
    

proc newSection* (
    kind: CKind,
    title: string = "",
    image: Image = newImage(),
    epigraph: seq[string] = @[],
    annotation: string = "",
): Section =
    ## Create book Section (chapter), unbound to any book
    ## Sections are either text or parent (may have everything 
    ## except chapter text)
    var section: Section
    if kind == tText:
        section = Section(
            title: title,
            image: image,
            epigraph: epigraph,
            annotation: annotation,
            kind: tText,
            text: ""
        )
    else:
        section = Section(
            title: title,
            image: image,
            epigraph: epigraph,
            annotation: annotation,
            kind: tSection,
            sections: @[]
        )
    return section
 

proc newSection* (
    chapter: string,
    title: string = "",
    image: Image = newImage(),
    epigraph: seq[string] = @[],
    annotation: string = "",
    flags: set[ParseFlags] = {}
): Section =
    ## Create new text section. Sections are either text
    ## or parent (may have everything except chapter text)
    var errors: seq[string] = @[]
    var xmlChapter = parseXml(
        newStringStream(chapter), "unknown_xml_doc",
        errors, xmlParseOpts
    )

    if not flags.contains(pNoParse):
        xmlChapter = xmlChapter.restrictTags(
            allow = textSectionTags, mapFrom = textMappedTags,
            mapTo = textTagMap
        )
    var section = newSection(
        kind = tText,
        title = title,
        image = image,
        epigraph = epigraph,
        annotation = annotation,
    )
    section.text = $xmlChapter
    return section
 

proc newSection* (
    sections: seq[Section] = @[],
    title: string = "",
    image: Image = newImage(),
    epigraph: seq[string] = @[],
    annotation: string = "",
): Section =
    ## Create new parent section. Sections are either text
    ## or parent (may have everything except chapter text)
    var section = newSection(
        kind = tSection,
        title = title,
        image = image,
        epigraph = epigraph,
        annotation = annotation,
    )
    section.sections = sections
    return section
    

proc isEmpty[T: ref object] (obj: T): bool =
    ## Check if book object is empty
    result = true
    for name, value in obj[].fieldPairs:
        when value is bool:
            if value:
                return false
        when value is string:
            if value != "":
                return false
        when value is int:
            if value > 0:
                return false
        when value is seq:
            if value.len > 0:
                return false
        when value is ref object:
            if not value.isEmpty:
                return false
    return result


proc fromXmlSection(xmlSection: XmlNode, flags:set[ParseFlags] = {}): Section = 
    ## Convert xml section object to Section
    var k:CKind
    var xmlSection = xmlSection
    if xmlSection.child("section").isNil:
        k = tText
    else:
        k = tSection
    var section = newSection(kind = k)
    if not flags.contains(pNoParse):
        discard xmlSection.filterSection

    for item in xmlSection:
        if item.tag == "title":
            section.title = item.innerHtml
        elif item.tag == "epigraph":
            section.epigraph.add(item.innerHtml)
        elif item.tag == "section":
            section.sections.add(
                item.fromXmlSection
            )
        elif item.tag == "annotation":
            section.annotation = item.innerHtml
        else:
            section.text &= $item
    return section

proc fromXmlSections(xmlSections: XmlNode, flags:set[ParseFlags] = {}): seq[Section] = 
    ## Convert XML book <body> xml sections to seq[Section] objects
    var sections: seq[Section] = @[]
    var xmlSection: XmlNode = newElement("section")
    var strayCount = 0
    for item in xmlSections.items:
        if item.tag != "section":
            # incorrect file, not in section tag
            # We need to accumulate "stray" tags into section
            xmlSection.add(item)
            strayCount.inc
        elif strayCount > 0:
            # incorrect file, not in section tags ended
            # We need to accumulate "stray" tags into section
            strayCount = 0
            sections.add(fromXmlSection(xmlSection))
            xmlSection = newElement("section")
            sections.add(fromXmlSection(item))
        else:
            sections.add(fromXmlSection(item))
    return sections


proc fromXml*[T: ref object] (obj: var T, xmlObject: XmlNode, flags:set[ParseFlags] = {}): T = 
    ## Convert book xml tree to book objects
    for name, value in obj[].fieldPairs:
        if name != "metadata":
            var xmlName = name
            xmlName = xmlName.replacef(re"([A-Z])", "-$1").toLowerAscii
            var child = xmlObject.child(xmlName)
            if not child.isNil:
                when value is string:
                    if name == "annotation":
                        obj.getField(name) = child.innerHtml
                    else:
                        obj.getField(name) = child.innerText
                when value is int:
                    obj.getField(name) = parseInt(
                        child.innerText)
                when value is seq[string]:
                    obj.getField(name) = xmlObject.findAll(xmlName).map(
                            proc(x: XmlNode): string = x.innerText)
                when value is seq[Section]:
                    obj.getField(name) = child.fromXmlSections(flags)
                when value is seq[Image]:
                    obj.binary = @[]
                    for child in xmlObject.findAll(xmlName):
                        obj.binary.add(
                            newImage(
                                child.attr("id"),
                                child.innerText
                            )
                        )
                when value is ref object:
                    obj.getField(name) = value.fromXml(child)
    return obj
    

proc toXml*[T: ref object] (obj: T): XmlNode =
    ## Convert book objects to book xml tree
    var oName = getXmlObjName($(obj.type))
    var xmlElement: XmlNode
    if oName == "book":
        xmlElement = newElement(
            "FictionBoook"
        )
        var attrs = {
            "xmlns": "http://www.gribuser.ru/xml/fictionbook/2.0",
            "xmlns:l": "http://www.w3.org/1999/xlink"
        }.toXmlAttributes
        xmlElement.attrs = attrs
    else:
        xmlElement = newElement(oName)
    for name, value in obj[].fieldPairs:
        if name != "metadata":
            var xmlName = name
            xmlName = xmlName.replacef(re"([A-Z])", "-$1").toLowerAscii
            when value is string or value is int:
                if ($value).len > 0:
                    if oName == "section" and name == "text":
                        var subElement = newVerbatimText($value)
                        xmlElement.add(subElement)
                    elif oName == "section" or name == "annotation":
                        var subElement = newElement(xmlName)
                        subElement.add(newVerbatimText($value))
                        xmlElement.add(subElement)
                    else:
                        var subElement = newElement(xmlName)
                        subElement.add(newText($value))
                        xmlElement.add(subElement)
            when value is seq[string]:
                for val in value:
                    if val.len > 0:
                        var subElement = newElement(xmlName)
                        if oName == "section":
                            subElement.add(newVerbatimText(val))
                        else:
                            subElement.add(newText(val))
                        xmlElement.add(subElement)
            when value is seq[Section]:
                var subElement = newElement(xmlName)
                for section in value:
                    subElement.add(section.toXml)
                xmlElement.add(subElement)
            when value is seq[Image]:
                for image in value:
                    var subElement = newElement(xmlName)
                    subElement.attrs = {
                        "id": image.getField("name"),
                        "content-type": "image/jpeg"
                    }.toXmlAttributes
                    subElement.add(newText(image.data))
                    xmlElement.add(subElement)
            when value is ref object:
                if not value.isEmpty:
                    xmlElement.add(value.toXml)       
    return xmlElement

proc `$`*[T: ref object] (obj: T): string =
    # Convert book's object of any level to xml and THEN to string
    return $(obj.toXml)

proc save* (b: Book, file: string = ""): string =
    ## Save `book` to `file` or to file in book.metadata.file
    var file = file
    if file == "":
        file = b.metadata.file
    var resultFile = open(file, fmWrite)
    resultFile.write(xmlHeader)
    resultFile.write($b)
    resultFile.close()

proc load* (b: var Book, file: string = ""): Book =
    ## Load `book` from `file` or from file in book.metadata.file
    var file = file
    if file == "":
        file = b.metadata.file
    var errors: seq[string]
    var tree = loadXml(file, errors, xmlParseOpts)
    b = fromXml(b, tree, b.metadata.flags)
    return b


proc getLastSection* (b: Book): Section = 
    ## Get book's last section/chapter
    return b.body[^1]


proc getLastSection* (s: Section): Section = 
    ## Get section's last subsection/subchapter
    if s.kind == tText:
        return s
    elif s.kind == tSection:
        return s.sections[^1]


proc newAuthor* (
    firstName: string = "",
    middleName: string = "",
    lastName: string = "",
    nickname: string = "",
    homePage: string = "",
    email: string = ""
): Author =
    ## Create book's Author object
    ## XML path description/title-info/author
    return Author(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        nickname: nickname,
        homePage: homePage,
        email: email
    )


proc getAuthorName* (b: Book, flags:set[CleanFlags]={cStrip, cNoSpec, cSquashSymbols}): string =
    ## Get book's author as string
    ## Can be either nickname or firstName-middleName-lastName if 
    runnableExamples:
      var b = newBook()
      var a = newAuthor(nickname=" Extremely~-cute   ")
      b.description.titleInfo.author = a
      doAssert b.getAuthorName == "Extremely-cute"
      a = newAuthor(firstName="Alexey", lastName="Tolstoy")
      b.description.titleInfo.author = a
      doAssert b.getAuthorName == "Alexey-Tolstoy"
      var da = newDocumentAuthor(
        firstName="Alexey", middleName="Nikola$yevich-", lastName="Tolstoy")
      b.description.documentInfo.author = da
      doAssert b.getAuthorName == "Alexey-Nikolayevich-Tolstoy"

    var title: string
    if b.description.titleInfo.author.nickname.len > 0:
        title = b.description.titleInfo.author.nickname
    else:
        var titleInfoTitle: seq[string] = @[]
        var documentInfoTitle: seq[string] = @[]

        if (
            b.description.titleInfo.author.firstName.len > 0
        ):
            titleInfoTitle.add(b.description.titleInfo.author.firstName)
        if (
            b.description.titleInfo.author.middleName.len > 0
        ):
            titleInfoTitle.add(b.description.titleInfo.author.middleName)
        if (
            b.description.titleInfo.author.lastName.len > 0
        ):
            titleInfoTitle.add(b.description.titleInfo.author.lastName)
        if (
            b.description.documentInfo.author.firstName.len > 0
        ):
            documentInfoTitle.add(b.description.documentInfo.author.firstName)
        if (
            b.description.documentInfo.author.middleName.len > 0
        ):
            documentInfoTitle.add(b.description.documentInfo.author.middleName)
        if (
            b.description.documentInfo.author.lastName.len > 0
        ):
            documentInfoTitle.add(b.description.documentInfo.author.lastName)
        if titleInfoTitle.len > documentInfoTitle.len:
            title = titleInfoTitle.join("-")
        else:
            title = documentInfoTitle.join("-")

    if flags.contains(cStrip):
        title = title.strip
    if flags.contains(cNoSpec):
        title = title.replacef(re"[\s\t~@#$%^&*!]+", "")
    if flags.contains(cNoSpec):
        title = title.replacef(re"\-+", "-")
    return title


proc newTranslator* (
    firstName: string = "",
    middleName: string = "",
    lastName: string = ""
): Translator =
    ## Create object representation of XML path /description/title-info/translator
    result = Translator(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName
    )

proc newTTitleInfo* (
    genres: seq[string] = @[],
    author: Author = newAuthor(),
    bookTitle: string = "",
    annotation: string = "",
    keywords: seq[string] = @[],
    date: string = "",
    coverpage: string = "",
    lang: string = "",
    srcLang: string = "",
    translator: Translator = newTranslator()
): TTitleInfo = 
    ## Create object representation of XML path /description/title-info
    ##
    ## This object contains info on original book text (author, translator,
    ## title, annotation, etc)
    result = TTitleInfo(
        genres: genres,
        author: author,
        bookTitle: bookTitle,
        annotation: annotation,
        keywords: keywords,
        date: date,
        coverpage: coverpage,
        lang: lang,
        srcLang: srcLang,
        translator: translator
    )

proc newDocumentAuthor* (
    firstName: string = "",
    middleName: string = "",
    lastName: string = ""
): DocumentAuthor =
    ## Create object representation of XML path /description/document-info.
    ## 
    ## This is fb2 document autor
    result = DocumentAuthor(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName
    )

proc newDDocumentInfo* (
    author: DocumentAuthor = newDocumentAuthor(),
    programUsed: string = "",
    date: string = "",
    srcUrl: string = "",
    srcOcr: string = "",
    id: string = "",
    version: string = "",
    history: string = ""
): DDocumentInfo =
    ## Create object representation of XML path /description/document-info.
    ## 
    ## This is this fb2 document information - who formed it,
    ## in which program, etc.
    result = DDocumentInfo(
        author: author,
        programUsed: programUsed,
        date: date,
        srcUrl: srcUrl,
        srcOcr: srcOcr,
        id: id,
        version: version,
        history: history
    )


proc newPPublishInfo* (
    bookName: string = "",
    publisher: string = "",
    city: string = "",
    year: int = 0,
    isbn: string = ""
): PPublishInfo =
    ## Create object representation of XML path /description/publish-info.
    ## 
    ## This is this paper printed document information - who issued it,
    ## in which year, city, etc.
    result = PPublishInfo(
        bookName: bookName,
        publisher: publisher,
        city: city,
        year: year,
        isbn: isbn
    )

proc newDescription* (
    titleInfo: TTitleInfo = newTTitleInfo(),
    documentInfo: DDocumentInfo = newDDocumentInfo(),
    publishInfo: PPublishInfo = newPPublishInfo()
): Description =
    ## Create object representation of XML path /description
    ## 
    ## This is metadata on this book - title, author, paper print and fb2 file info.
    result = Description(
        titleInfo: titleInfo,
        documentInfo: documentInfo,
        publishInfo: publishInfo
    )

proc addSubSections* (
    parent: var Section,
    children: openArray[Section]
): Section =
    ## Add subsections to parent section
    ## parent must be of tSection kind
    assert parent.kind == tSection
    
    parent.sections.add(children)
    result = parent

proc formatFilename(templ: string, b: Book): string =
    ## Format filename from metadata template
    var res = templ
    res = res.replace("{bookTitle}", b.description.titleInfo.bookTitle)
    res = res.replace("{authorName}", b.getAuthorName)
    res = res.replace("{sectionsNum}", $(b.body.len))
    return res


proc refresh(m: var Metadata, book: Book): Metadata =
    ## Refresh metadata to acquire new filename (if needed)
    if m.file.len == 0:
        m.file = formatFilename(m.fileTemplate, book)
    return m


proc newMetadata* (
    flags: set[ParseFlags] = {},
    file: string = "",
    fileTemplate: string = "{bookTitle}_{authorName}_1-{sectionsNum}.fb2"
): Metadata = 
    ## Create unbound object with book's metainfo
    var m = Metadata(
        flags: flags,
        file: file,
        fileTemplate: fileTemplate
    )
    return m


proc newMetadata* (
    book: var Book,
    flags: set[ParseFlags] = {},
    file: string = "",
    fileTemplate: string = "{bookTitle}_{authorName}_1-{sectionsNum}.fb2"
): Metadata = 
    ## Create object with book's metainfo bound to selected book
    var m = newMetadata(flags, file, fileTemplate)
    m = m.refresh(book)
    book.metadata = m
    return m


proc newBook* (
    description: Description = newDescription(),
    body: seq[Section] = @[],
    metadata: Metadata = newMetadata()
): Book =
    ## Create new book
    ##
    ## See also:
    ## * `newDescription proc <#newDescription,TTitleInfo,DDocumentInfo,PPublishInfo>`_ - to create book's description
    ## * `newSection proc <#newSection,CKind,string,Image,seq[string],string>`_ to create empty section of chosen kind
    ## * `newSection proc <#newSection,string,string,Image,seq[string],string,set[ParseFlags]>`_ to create text section
    ## * `newSection proc <#newSection,seq[Section],string,Image,seq[string],string>`_ to create parent to other subsections section
    ## * `newImage proc <#newImage,string,string>`_ to create new binary (image)
    ## * `newMetadata proc <#newMetadata,set[ParseFlags],string,string>`_ - to create unbound metadata
    ## * `newMetadata proc <#newMetadata,Book,set[ParseFlags],string,string>`_ to create metadata and add to an existing book
    result = Book(
        description: description,
        body: body,
        metadata:  metadata
    )
    
proc fromXml* (xmlBook: XmlNode): Book =
    ## Convert book xml tree to book objects
    var book = newBook()
    result = book.fromXml(xmlBook)

proc addBookHeader* (book: var Book, description: Description): Book = 
    book.description = description
    return book

proc addChapter* (book: var Book, chapter: Section): Book =
    ## Add existing chapter to the existing book
    book.body.add(chapter)
    return book

proc addChapter* (
    book: var Book,
    chapter: string,
    title: string = "",
    image: Image = newImage(),
    epigraph: seq[string] = @[],
    annotation: string = "",
    flags: set[ParseFlags] = {}
): Book =
    ## Create and add new chapter to the existing book
    var section = newSection(
        chapter, title, image, epigraph, annotation, flags
    )
    book.body.add(section)
    result = book


proc appendFiles* (
    book: var Book,
    subbooks: seq[string],
): Book =
    ## Add several "subbooks" files to the existing book (append all their
    ## sections to this book)
    for subbook in subbooks:
        var b = newBook()
        b = b.load(subbook)
        for c in b.body:
            book = book.addChapter(c)

    return book


proc appendFiles* (
    book: var Book,
    directory: string,
): Book =
    ## Add all files (sections in them) in directory to the existing book
    var files = collect(newSeq):
        for fileName in walkFiles(directory & "*.fb2"):
            if cmpPaths(fileName, book.metadata.file) != 0:
                fileName
    book = book.appendFiles(files)

    return book


proc merge* (
    files: seq[string]
): Book =
    ## Make a book from `files[0]` and add other `files[1 .. ^1]` to this book
    var book = newBook()
    book = book.load(files[0])
    return book.appendFiles(files[1 .. ^1])


proc merge* (
    directory: string
): Book =
    ## Make a book from first file in directory and add other files to this book.
    ## Files are taken in alphabetic order
    var files = collect(newSeq):
        for fileName in walkFiles(directory / "*.fb2"):
            fileName
    return merge(files)
    

    
proc appendChapter* (
    chapter: var Section,
    text: string
): Section =
    ## Add more text to the end of the chapter
    ## Only works with chapters of the tText type
    assert chapter.kind == tText
    
    chapter.text &= text
    result = chapter



