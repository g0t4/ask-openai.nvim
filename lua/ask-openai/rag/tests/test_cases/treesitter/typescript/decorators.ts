function sealed(constructor: Function) {
    Object.seal(constructor);
    Object.seal(constructor.prototype);
};

function log(target: any) {};

@sealed
class SimpleTest {
    @log
    greet(name: string): string {
        return `Hello, ${name}`;
    };
};


// decorators cannot be put on:
//    enums, type aliases, interfaces
