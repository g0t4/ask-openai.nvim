from tree_sitter import Parser
from tree_sitter_language_pack import get_language, get_parser

from lsp.logs import get_logger

logger = get_logger(__name__)

parsers_by_language = {}

def _get_cached_parser(language):
    if language in parsers_by_language:
        return parsers_by_language[language]
    with logger.timer('get_parser' + language):
        parser = get_parser(language)
        parsers_by_language[language] = parser
    return parser

def get_cached_parser_for_path(path) -> tuple[Parser | None, str]:

    language = path.suffix[1:]
    if language is None:
        # PRN shebang?
        return None, ""
    elif language == "txt":
        # no need to log... just skip txt files
        return None, "txt"
    elif language == "py":
        language = "python"
    elif language == "sh":
        language = "bash"
    elif language == "lua":
        language = "lua"
    elif language == "js":
        language = "javascript"
    elif language == "ts":
        language = "typescript"
    elif language == "c":
        language = "c"
    elif language == "cpp":
        language = "cpp"
    elif language == "cs":
        language = "csharp"
    elif language == "bash":
        language = "bash"
    elif language == "fish":
        language = "fish"
    elif language == "vim":
        language = "vim"
    elif language == "ps1":
        language = "powershell"
    elif language == "rs":
        language = "rust"
    elif language == "json":
        language = "json"
    else:
        # *** https://github.com/Goldziher/tree-sitter-language-pack#readme
        # not (yet?): zsh, snippet, applescript?

        # PRN attempt to use extension as is? as fallback?
        logger.warning(f'no tree-sitter parser for: {language=}')
        return None, language

    return _get_cached_parser(language), language
