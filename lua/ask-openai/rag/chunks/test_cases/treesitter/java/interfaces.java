public interface Shape {
    double area();
    default double scaled(double factor) {
        return area() * factor;
    }
}
