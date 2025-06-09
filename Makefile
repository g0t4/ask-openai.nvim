
tags:
        ctags -R

tests:
		fd "\.tests\." | xargs -I_ nvim --headless -c 'PlenaryBustedFile _'

clean:
        rm -f tags

