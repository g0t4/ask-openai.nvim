llama-server -hf Qwen/Qwen3-Embedding-0.6B-GGUF:Q8_0 \
    --host 0.0.0.0 --port 8013 \
    -embeddings

# * We recommend enabling flash_attention_2 for better acceleration and memory saving.
# model = AutoModel.from_pretrained('Qwen/Qwen3-Embedding-0.6B',
#   attn_implementation="flash_attention_2",
#   torch_dtype=torch.float16).cuda()

# ? --batch-size 2048 --ubatch-size 2048 \
