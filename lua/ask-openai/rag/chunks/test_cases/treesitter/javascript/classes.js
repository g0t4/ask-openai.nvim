class Calculator {
    add(a, b) {
        return a + b;
    }

    static multiply(a, b) {
        return a * b;
    }

    get value() {
        return this._value;
    }
}
