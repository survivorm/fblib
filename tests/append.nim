import fblib

proc test_append_files()=
    var book = newBook()
    book = book.load("./tests/data/1.fb2")
    book = book.appendFiles(@["./tests/data/3.fb2", "./tests/data/2.fb2"])
    assert book.body.len == 4
    assert book.body[0].title == "Chapter 1"
    assert book.body[1].title == "Chapter 4"
    assert book.body[2].text == "<p>Chapter text 2</p>"
    assert book.body[3].title == "Chapter 3"

test_append_files()
