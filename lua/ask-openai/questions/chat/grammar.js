// ideas/steps from: https://chatgpt.com/c/69174d02-b1fc-8333-b8a6-6ecace15a383
//  a new file type  like askbuffer or askchatbuffer
//  folds.scm, highlights.scm... optional: indents.scm, textobjects.scm
//  TODO make sections recognize content as markdown

module.exports = grammar({
  name: 'askbuffer',

  rules: {
    document: $ => repeat($.block),

    block: $ => choice(
      $.role_header,
      $.reasoning_block,
      $.tool_call_block,
      $.metadata_block,
      $.text_block,
    ),

    role_header: $ => choice(
      seq('user', '\n'),
      seq('assistant', '\n'),
      seq('system', '\n'),
    ),

    reasoning_block: $ => seq(
      '≡≡≡ reasoning ≡≡≡', // or whatever markers you decide
      repeat(choice(/[^\n]*/)),
      '≡≡≡ end ≡≡≡',
    ),

    tool_call_block: $ => seq(
      'tool:', /.*/,
      repeat($.tool_call_line),
    ),

    tool_call_line: $ => /.*/,

    metadata_block: $ => seq(
      '{', repeat(/[^}]/), '}'
    ),

    text_block: $ => /[^\n]+/,
  },
});

