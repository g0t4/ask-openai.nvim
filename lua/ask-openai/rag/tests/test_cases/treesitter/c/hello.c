#include "calc.c"
#include <stdio.h>

int main() {
    printf("Hello, World!\n");

    Calculator* calc = calc_new();
    if (calc) {
        calc_set_expression(calc, "2 + 3 * 4");
        double result = calc_evaluate(calc);
        printf("Result: %f\n", result);
        calc_clear(calc);
        free(calc);
    }

    return 0;
}

