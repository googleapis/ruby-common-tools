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

require "securerandom"
require_relative "resource/gen-rb/phonebook_constants"
require_relative "resource/gen-rb/twitter_constants"

class Generator
  attr_reader :size
  attr_reader :type
  attr_reader :pattern

  def initialize type, pattern, size
    @type = type
    @pattern = pattern
    @size = size
  end

  def generate
    case type
    when "syntetic"
      case pattern
      when "repeated"
        syntetic_repeated
      when "semi_repeated"
        syntetic_semi_repeated
      when "random"
        syntetic_random
      else
        raise "Unknown data pattern!!"
      end
    when "realistic"
      case pattern
      when "repeated"
        realistic_repeated
      when "semi_repeated" || "random"
        realistic_semi_repeated
      else
        raise "Unknown data pattern!!"
      end
    else
      raise "Unknown data type!!"
    end
  end

  private

  def syntetic_repeated
    message = "Hello world"
    count = size / message.length
    message * count
  end

  def syntetic_semi_repeated
    message = 10.times.map { SecureRandom.random_bytes(15) }.join(" ")
    count = size / message.length
    message * count
  end

  def syntetic_random
    SecureRandom.random_bytes size
  end

  def realistic_repeated
    serializer = Thrift::Serializer.new
    phone_book = PhoneBook.new
    message = ""
    phone_book.people = []
    while message.length < size
      phone_book.people.append generate_person
      message = serializer.serialize phone_book
    end
    message
  end

  def realistic_semi_repeated
    serializer = Thrift::Serializer.new
    twitter = Twitter.new
    message = ""
    twitter.spaces = []
    while message.length < size
      twitter.spaces.append generate_space
      message = serializer.serialize twitter
    end
    message
  end

  def generate_person
    person = Person.new
    person.name = generate_name
    person.phones = []
    2.times do
      person.phones.append generate_phone
    end
    person
  end

  def generate_name
    name = Name.new
    name.firstName = SecureRandom.alphanumeric 10
    name.lastName = SecureRandom.alphanumeric 10
    name
  end

  def generate_phone
    phone = Phone.new
    phone.number = SecureRandom.random_number 10
    phone
  end

  def generate_space
    space = Space.new
    space.profile = generate_profile
    space.homePage = generate_home_page
    space.timeline = generate_timeline
    space.followers = []
    space.followees = []
    2.times do
      space.followers.append generate_profile
      space.followees.append generate_profile
    end
    space
  end

  def generate_home_page
    home_page = HomePage.new
    home_page.profile = generate_profile
    home_page.profileTweets = []
    5.times do
      home_page.profileTweets.append generate_tweet
    end
    home_page
  end

  def generate_timeline
    timeline = Timeline.new
    timeline.profileTweets = []
    timeline.followerTweets = []
    timeline.followeeTweets = []
    5.times do
      timeline.profileTweets.append generate_tweet
      timeline.followerTweets.append generate_tweet
      timeline.followeeTweets.append generate_tweet
    end
    timeline
  end

  def generate_tweet
    tweet = Tweet.new
    tweet.profile = generate_profile
    tweet.text = SecureRandom.alphanumeric 10
    tweet.loc = generate_location
    tweet
  end

  def generate_profile
    profile = Profile.new
    profile.userId = SecureRandom.random_number 10
    profile.person = generate_person
    profile.bio = SecureRandom.alphanumeric 10
    profile.hometown = generate_address
    profile.hobby = SecureRandom.alphanumeric 10
    profile.dob = SecureRandom.alphanumeric 10
    profile.occupation = SecureRandom.alphanumeric 10
    profile.jobs = []
    3.times do
      profile.jobs.append generate_job
    end
    profile.educations = [generate_education]
    profile
  end

  def generate_location
    location = Location.new
    location.latitude = SecureRandom.random_number
    location.longitude = SecureRandom.random_number
    location
  end

  def generate_address
    address = Address.new
    address.street = SecureRandom.alphanumeric 10
    address.apartment = SecureRandom.alphanumeric 10
    address.city = SecureRandom.alphanumeric 10
    address.state = SecureRandom.alphanumeric 10
    address.country = SecureRandom.alphanumeric 10
    address.zipCode = SecureRandom.random_number 10
    address.location = generate_location
    address
  end

  def generate_company
    company = Company.new
    company.name = SecureRandom.alphanumeric 10
    company.headQuarter = generate_address
    company.offices = []
    5.times do
      company.offices.append generate_address
    end
    company.establishDate = SecureRandom.alphanumeric 10
    company.description = SecureRandom.alphanumeric 10
    company.employeeCount = SecureRandom.random_number 10
    company.founders = []
    2.times do
      company.founders.append generate_person
    end
    company
  end

  def generate_job
    job = Job.new
    job.company = generate_company
    job.designation = SecureRandom.alphanumeric 10
    job.startDate = SecureRandom.alphanumeric 10
    job.endDate = SecureRandom.alphanumeric 10
    job.address = generate_address
    job
  end

  def generate_institute
    institute = Institute.new
    institute.name = SecureRandom.alphanumeric 10
    institute.address = generate_address
    institute.establishDate = SecureRandom.alphanumeric 10
    institute.studentCount = SecureRandom.random_number 10
    institute.director = SecureRandom.alphanumeric 10
    institute
  end

  def generate_education
    education = Education.new
    education.institute = generate_institute
    education.startDate = SecureRandom.alphanumeric 10
    education.endDate = SecureRandom.alphanumeric 10
    education.major = SecureRandom.alphanumeric 10
    education.degree = SecureRandom.alphanumeric 10
    education.gpa = SecureRandom.random_number
    education
  end
end
