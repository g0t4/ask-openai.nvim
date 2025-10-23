FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04
WORKDIR /workspace

RUN apt-get update \
    && apt-get install -y \
    python3 python3-venv python3-pip \
    build-essential ninja-build git \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install --upgrade pip setuptools wheel

RUN pip install torch torchvision --extra-index-url https://download.pytorch.org/whl/cu128

RUN pip install \
    accelerate>=1.9.0 aiofiles>=24.1.0 assertpy>=1.1 \
    asyncio>=3.4.3 faiss-cpu>=1.11.0 httpx>=0.28.1 \
    ipykernel>=6.29.5 matplotlib>=3.10.3 msgpack>=1.1.1 \
    numpy>=2.3.0 pathspec>=0.12.1 pydantic>=2.11.7 \
    pygls==2.0.0a6 pympler>=1.1 pyright>=1.1.404 \
    pytest>=8.4.1 pytest-asyncio>=1.1.0 pytest-watch>=4.2.0 \
    rank-bm25>=0.2.2 requests>=2.32.3 rich>=14.0.0 \
    sentence-transformers>=4.1.0 tree-sitter>=0.25.2 \
    tree-sitter-language-pack>=0.10.0 yapf>=0.43.0

# TODO move up above later
ENV CUDA_HOME=/usr/local/cuda
ENV MAX_JOBS=4

RUN pip install ninja

# move these up later, keep here so I dont invalidate build caches for above layers
ENV TORCH_CUDA_ARCH_LIST="8.0;9.0"
ENV MAX_JOBS=1
RUN pip install flash-attn --no-build-isolation -v
# build shits a brick, appears to be OOM ("Killed" is what I see in logs)
#  giving up for now, takes way too fucking long to run one test without parallelizing the build


COPY . /workspace

