package main

import "fmt"

// Greeting says hello.
func Greeting(name string) string {
	return fmt.Sprintf("Hello, %s!", name)
}

type Person struct {
	FirstName string
	LastName  string
}

func (p Person) FullName() string {
	return p.FirstName + " " + p.LastName
}

func (p *Person) SetLastName(name string) {
	p.LastName = name
}

type Shape interface {
	Area() float64
}

type Greeter interface {
	Greet(name string) string
}

type ID = string

func main() {
	fmt.Println(Greeting("World"))
}
