#!/usr/bin/env fish

set original "https://huggingface.co/api/resolve-cache/models/meta-models/Muse-Glimmer-30B/97c77dff50b2797bcc558fa2d909761dbc575c59/chat_template.jinja?%2Fmeta-models%2FMuse-Glimmer-30B%2Fresolve%2Fmain%2Fchat_template.jinja=&etag=%228a8673897ed588c171d50088c89e25360130abe6%22"
wget $original --output-document original.jinja
