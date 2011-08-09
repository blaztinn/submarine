man1_MANS = submarine.man
html_DATA = README.html

EXTRA_DIST= $(man1_MANS) $(html_DATA)

README.html: ../README.asciidoc
	asciidoc -o README.html ../README.asciidoc
