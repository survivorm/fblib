import fblib

proc test_merge_files()=
    var book = merge(@["./tests/data/1.fb2", "./tests/data/2.fb2", "./tests/data/3.fb2"])
    assert book.body.len == 4
    assert book.body[0].title == "Chapter 1"
    assert book.body[1].text == "<p>Chapter text 2</p>"
    assert book.body[2].title == "Chapter 3"
    assert book.body[3].text == "<p>Chapter text 4</p>"

test_merge_files()

proc test_merge_directory()=
    var book = merge("./tests/data/")
    assert book.body.len == 5
    assert book.body[4].text == "<p>какой-то текст</p>"

test_merge_directory()
