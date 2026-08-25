def greet(name):
    return "Hello, " + name


class Person:
    def __init__(self, name):
        self.name = name

    def full_name(self, last):
        return self.name + " " + last


def main():
    person = Person("Ada")
    print(greet(person.full_name("Lovelace")))
