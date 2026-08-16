function add(a, b) {
    return a + b;
}

function* range(start, end) {
    for (let i = start; i < end; i++) {
        yield i;
    }
}
