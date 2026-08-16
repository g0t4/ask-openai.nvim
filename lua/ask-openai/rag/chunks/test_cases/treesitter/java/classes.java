public class Person {
    private String name;

    public Person(String name) {
        this.name = name;
    }

    public String getName() {
        return name;
    }

    public static Person create(String name) {
        return new Person(name);
    }
}
