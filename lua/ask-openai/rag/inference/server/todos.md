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

## signal hotpath ideas/notes

- let client signal that hotpath is done
    - cache can be reused during "hotpath"... i.e. re-indexing a codebase
    - biggest benefit of cleanup is gonna be for re-indexing
    - Lang Server one off file updated won't matter much

- FTR empty_cache after each batch in after_send below:
- when rag_rebuild this entire repo, resulted in no increase in duration
- shouldn't be necessary but if needed just a heads up

- PRN ignore signal if no batches run since last
    - OR if less than threshold?
    - OR if memory isn't high?
    - I say this b/c client should always signal when hotpath is done
        - and client should not think about impact on server, let server handle that or all clients
