#include <iostream>
#include <string.h>
using namespace std;
union Data {
    int i;
    float f;
    char str[20];
};
int main() {
    Data data;
    data.i = 10;
    cout << "data.i : " << data.i << endl;
    cout << " data.f : " << data.f << endl;
    // the value of i above will be overwritten by f below
    data.f = 220.5;
    cout << " data.i : " << data.i << endl;
    cout << " data.f : " << data.f << endl;
    strcpy(data.str, "C Programming");
    cout << " data.str : " << data.str << endl;
    cout << " data.i : " << data.i << endl;
    cout << " data.f : " << data.f << endl;



    return 0;
}
