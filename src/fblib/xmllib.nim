import xmltree
import sequtils
import strutils
import sets
import re
     

proc restrictTags*(n: var XmlNode, prohibit, allow, mapFrom, mapTo: openArray[string] = @[]): var XmlNode =
  ## Prohibit certain tags from `n` decendants. Tags are not deleted, rather, their
  ## children are moved to upper level, as if parent tag never existed
  ## You must supply either `prohibit` or `allow`. If tags are not in `allow`,
  ## and not mapped, they are prohibited
  ## Map other tags from list a to list b `mapFrom` must have same length as
  ## `mapTo`.
  ## n should be xnElement type
  runnableExamples:
    import xmltree
    var g = newElement("myTag")
    var k = newElement("body")
    var l = newElement("div")
    var textNode = newElement("span")
    textNode.add newText("Some text")
    l.add newText("Some text of upper level")
    l.add textNode
    k.add l
    g.add k
    g.add newComment("this is comment")
    var g0 = g
    var results = """<myTag>
  <p>Some text of upper level  <span>Some text</span></p><!-- this is comment -->
</myTag>"""
    g0 = g0.restrictTags(prohibit = @["body"], mapFrom = @["div"], mapTo = @["p"])
    assert $g0 == results
    var g1 = g
    g1 = g1.restrictTags(allow = @["p", "span"], mapFrom = @["div"], mapTo = @["p"])
    assert $g1 == results

  result = n
  assert prohibit.len == 0 or allow.len == 0
  assert mapTo.len == mapFrom.len
  assert n.kind == xnElement
  var processParents = @[n]
  while processParents.len > 0:
    var changed = true
    var parent = processParents.pop()
    while changed:
      changed = false

      var index = -1
      for child in parent.mitems:
        index.inc
        # we don't process elements other than tags, they're left 'as is'
        if child.kind() != xnElement:
          continue
        var mapIndex = mapFrom.find(child.tag)
        if mapIndex > -1:
          child.tag = mapTo[mapIndex]
          continue
        elif (
          prohibit.find(child.tag) > -1 or
          (allow.len > 0 and allow.find(child.tag) == -1)
        ):
          parent.replace(index, toSeq(child.items))
          changed = true
          break

    processParents.add(toSeq(parent.items).filter(
            proc(x: XmlNode): bool = x.kind == xnElement
        )
    )
    result = n


proc innerHtml*(n: XmlNode): string = 

    result = ""
    for element in n.items():
        result &= $element
            
    
