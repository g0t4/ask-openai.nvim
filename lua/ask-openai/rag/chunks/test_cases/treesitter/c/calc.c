
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef struct Calculator {
    double result;
    char* expression;
    size_t expr_len;
} Calculator;

Calculator* calc_new() {
    Calculator* calc = (Calculator*)malloc(sizeof(Calculator));
    if (calc) {
        calc->result = 0.0;
        calc->expression = NULL;
        calc->expr_len = 0;
    }
    return calc;
}

void calc_free(Calculator* calc) {
    if (calc) {
        free(calc->expression);
        free(calc);
    }
}

void calc_set_expression(Calculator* calc, const char* expr) {
    if (!calc || !expr) return;

    free(calc->expression);
    calc->expr_len = strlen(expr);
    calc->expression = (char*)malloc(calc->expr_len + 1);
    if (calc->expression) {
        strcpy(calc->expression, expr);
    }
}

double calc_evaluate(Calculator* calc) {
    if (!calc || !calc->expression) return 0.0;

    // Simple expression evaluator
    double result = 0.0;
    double current = 0.0;
    char operator = '+';

    size_t i = 0;
    while (i < calc->expr_len) {
        // Skip whitespace
        while (i < calc->expr_len && isspace(calc->expression[i])) {
            i++;
        }

        if (i >= calc->expr_len) break;

        // Parse number
        if (isdigit(calc->expression[i]) || calc->expression[i] == '.') {
            double num = 0.0;
            int decimal = 0;
            double decimal_multiplier = 1.0;

            while (i < calc->expr_len && (isdigit(calc->expression[i]) || calc->expression[i] == '.')) {
                if (calc->expression[i] == '.') {
                    decimal = 1;
                } else {
                    if (decimal) {
                        decimal_multiplier /= 10.0;
                        num += (calc->expression[i] - '0') * decimal_multiplier;
                    } else {
                        num = num * 10.0 + (calc->expression[i] - '0');
                    }
                }
                i++;
            }

            switch (operator) {
                case '+':
                    result += num;
                    break;
                case '-':
                    result -= num;
                    break;
                case '*':
                    result *= num;
                    break;
                case '/':
                    if (num != 0.0) {
                        result /= num;
                    }
                    break;
            }
        } else {
            // Handle operator
            operator = calc->expression[i];
            i++;
        }
    }

    calc->result = result;
    return result;
}

double calc_get_result(Calculator* calc) {
    return calc ? calc->result : 0.0;
}

void calc_clear(Calculator* calc) {
    if (calc) {
        calc->result = 0.0;
        free(calc->expression);
        calc->expression = NULL;
        calc->expr_len = 0;
    }
}


