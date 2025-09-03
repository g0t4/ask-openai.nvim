## inference server improvement ideas

- improve efficiency during large re-indexing runs
    - Pad + fix shapes: pad seq to a multiple of 128 and use a fixed batch size → steadier kernels & fewer allocs.
        - Pre-allocate buffers: create max-size input*ids/attn_mask and an output tensor once on GPU; .copy*() into them each batch.
        - CUDA Graphs: with static shapes, capture the forward once and replay → big latency cut.
            - IIUC think query execution plan in SQL, b/c of fixed buffer size (padded to 128)
        - measure timing before going hog wild, IIAC can shave 10% off of batch timing
    - and/or I already sort batches on sequence length, so:
        - I could pre-alloc on 128 boundary as the batches come in and when I cross into a bigger boundary, then pre-alloc again
        - keep using pre-allocated buffer until next 128 boundary crossed
    - improve client ordering too?
        - !! outlier sequences, like one or a few that are 10x longer than the rest...
            - run in own batch or if a few really long ones, batch just them (not the full batch size always)
        - oh actually batch size aligned with similar length sequences instead of always 8 would make sense
        - client is in best position to make many of these batching decisions

- Transfers: tokenize on CPU, use pin_memory=True and .to(device, non_blocking=True).

- Allocator knobs: PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128,expandable_segments:True.

