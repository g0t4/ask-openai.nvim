

TESTED JSON RPC over STDIO for the command and it returns one line only... I must have buffering in my client

OK issue might actually be that JSON payload is split if it is large across multiple server STDIO writes?
- I glued together two failed attempts to decode JSON that worked when combined but obviously not apart
- see commands.log copy in current dir...
- watch tail_ask_predictions log file for failed decodes...
    PRN I need to do something to surface failures in decode (if its the final decode? do I know that?)...
    TODO how can I detect split across lines?

    see ask_predictions_split_decode_failure.log... shows the JSONRPC message is indeed split!!!
       see second log entry at end => JSONRPC fields so it is a JSON RPC issue I need to support!

Ask Qwen3.5 27B Distill Claude Opus to run the following command and it will hang (it appears)...
- *** not model related (IIGC)
- TODO WHY does timeout not apply?
  several cases model (qwen3.5 distill) specifically set timeout to 10000 and 30000 (is my timeout in seconds and not ms?)

```vim
AskQuestion /tools run system_profiler SPUSBDataType SPThunderboltDataType -json and summarizer
```

```
system_profiler SPUSBDataType SPThunderboltDataType -json
```

## other hang notes (not the above command)

I suspect a few cases trigger a hang due to blocking for input? Though I would think these should timeout.
