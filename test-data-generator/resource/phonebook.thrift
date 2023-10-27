# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

enum PhoneType {
  MOBILE = 0,
  HOME = 1,
  WORK = 2
}

struct Name {
  1: string firstName,
  2: string lastName
}

struct Phone {
  1: PhoneType type = PhoneType.MOBILE,
  2: i32       number
}

struct Person {
  1: Name        name,
  2: list<Phone> phones,
}

struct PhoneBook {
  1: list<Person> people,
}
