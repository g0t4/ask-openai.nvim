from datetime import datetime

class Person():

    def __init__(self, first_name, last_name, dob):
        self.first_name = first_name
        self.last_name = last_name
        self.dob = dob

    def say_hi(self):
        return f'Hi, {self.first_name} {self.last_name}!'

    def is_of_age(self):
        current_year = datetime.now().year
        return (current_year - self.dob.year) >= 18

    def __str__(self):
        return f'Person({self.first_name}, {self.last_name}, {self.dob})'
