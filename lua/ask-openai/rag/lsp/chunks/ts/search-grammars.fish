#!/usr/bin/env fish

function who_uses
    set what $argv[1]
    if test -z "$what"
        echo "Usage: who_uses function_definition"
        return 1
    end

    gh search code --owner tree-sitter --owner tree-sitter-grammars --filename grammar.json $what
end
