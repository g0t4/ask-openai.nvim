#!/usr/bin/env fish

function who_uses
    set what $argv[1]
    if test -z "$what"
        echo "Usage: who_uses function_definition"
        return 1
    end

    gh search code --owner tree-sitter --owner tree-sitter-grammars --filename grammar.json $what
end

function search_partial
    set partial $argv[1]
    if test -z "$partial"
        echo "Usage: who_uses function_definition"
        return 1
    end

    gh search code --owner tree-sitter --owner tree-sitter-grammars --filename grammar.json "$partial" --limit 100 | grep -Eo "\w*$partial\w*" | sort | uniq
end
