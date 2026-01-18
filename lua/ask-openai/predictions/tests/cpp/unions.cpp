#include <iostream>
using namespace std;
union Data {
    int i;
    float f;
    char str[20];
};
int main() {
    // show how union works
    Data data;
    data.i = 10;
    cout << "data.i : " << data.i << endl;
    cout << "d

    return 0;
}
