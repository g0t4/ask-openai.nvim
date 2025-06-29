def chunk_id_to_faiss_id(chunk_id: str) -> int:
    """Convert chunk ID to FAISS ID (signed int64)"""
    # Convert hex string directly to int and mask for signed int64
    hash_int = int(chunk_id, 16)
    # Mask to fit in signed int64 (0x7FFFFFFFFFFFFFFF = 2^63 - 1)
    return hash_int & 0x7FFFFFFFFFFFFFFF
