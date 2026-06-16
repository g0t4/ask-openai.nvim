type TriggerMacroSettings = {
    macro_uuid?: string;
    parameter?: string;
    dynamic_title?: string;
};

enum Direction {
    Up,
    Down,
    Left,
    Right,
}

interface Point {
    x: number;
    y: number;
}

