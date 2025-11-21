My goal here is to have an initial chunk of code that is valid in more than one language...

Several cursor spots with suggestions would then need to know the language to reliably generate valid predictions:

- at end of file, to add a main method
- in speak func, to print a message,  i.e. "hi"
- at top to add #include (for std::cout when used in speak)

- Ya know there are subtle differences that would be VERY rare to avoid... I don't know that the language is needed, at least not to DISAMBIGUATE two possible languages, maybe when a file is brand new it could help or maybe if a model is generating a ton of markdown, it might be a good reminder... lets wait and see

That way I can test different approaches to including the language information:
- Filename
- Language specific comment (comment might also give some away!)
- Instruction/message before FIM?
- using special tokens:
    <|repo_name|> speaking in lua
    <|file_sep|> speak.lua
    <|fim_prefix|>...<|fim_suffix|>...<|fim_middle|>
    - is it possible SPM would work better for a promp with additional info? hunch is it wouldn't matter

