
tags:
		ctags -R

redo_tags:
		wc -l tags && trash tags && make tags && wc -l tags
		# show wordcount before and after for how much is added/removed since last build

tests:
		fd "\.tests\." | xargs -I_ nvim --headless -c 'PlenaryBustedFile _'

clean:
		rm -f tags

