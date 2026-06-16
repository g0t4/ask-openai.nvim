function add(a: number, b: number): number {
    return a + b;
}
function subtract(a: number, b: number): number {
    return a - b;
}
function multiply(a: number, b: number): number {
    return a * b;
}
function divide(a: number, b: number): number {
    return a / b;
}
class Calculator {
    add(a: number, b: number): number {
        return add(a, b);
    }
    subtract(a: number, b: number): number {
        return subtract(a, b);
    }
    multiply(a: number, b: number): number {
        return multiply(a, b);
    }
    divide(a: number, b: number): number {
        return divide(a, b);
    }
}
