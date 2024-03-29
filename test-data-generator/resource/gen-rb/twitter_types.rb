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
#
# Autogenerated by Thrift Compiler (0.17.0)
#
# DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
#

require "thrift"
require_relative "phonebook_types"


module TweetType
  TWEET = 0
  RETWEET = 2
  DM = 10
  REPLY = 11
  VALUE_MAP = { 0 => "TWEET", 2 => "RETWEET", 10 => "DM", 11 => "REPLY" }.freeze
  VALID_VALUES = Set.new([TWEET, RETWEET, DM, REPLY]).freeze
end

class Location; end

class Address; end

class Company; end

class Job; end

class Institute; end

class Education; end

class Profile; end

class Tweet; end

class Timeline; end

class HomePage; end

class Space; end

class Twitter; end

class Location
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  LATITUDE = 1
  LONGITUDE = 2

  FIELDS = {
    LATITUDE => { type: ::Thrift::Types::DOUBLE, name: "latitude" },
    LONGITUDE => { type: ::Thrift::Types::DOUBLE, name: "longitude" }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Address
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  STREET = 1
  APARTMENT = 2
  CITY = 3
  STATE = 4
  COUNTRY = 5
  ZIPCODE = 6
  LOCATION = 7

  FIELDS = {
    STREET => { type: ::Thrift::Types::STRING, name: "street" },
    APARTMENT => { type: ::Thrift::Types::STRING, name: "apartment" },
    CITY => { type: ::Thrift::Types::STRING, name: "city" },
    STATE => { type: ::Thrift::Types::STRING, name: "state" },
    COUNTRY => { type: ::Thrift::Types::STRING, name: "country" },
    ZIPCODE => { type: ::Thrift::Types::I32, name: "zipCode" },
    LOCATION => { type: ::Thrift::Types::STRUCT, name: "location", class: ::Location }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Company
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  NAME = 1
  HEADQUARTER = 2
  OFFICES = 3
  ESTABLISHDATE = 4
  DESCRIPTION = 5
  EMPLOYEECOUNT = 6
  FOUNDERS = 7

  FIELDS = {
    NAME => { type: ::Thrift::Types::STRING, name: "name" },
    HEADQUARTER => { type: ::Thrift::Types::STRUCT, name: "headQuarter", class: ::Address },
    OFFICES => { type: ::Thrift::Types::LIST, name: "offices",
element: { type: ::Thrift::Types::STRUCT, class: ::Address } },
    ESTABLISHDATE => { type: ::Thrift::Types::STRING, name: "establishDate" },
    DESCRIPTION => { type: ::Thrift::Types::STRING, name: "description" },
    EMPLOYEECOUNT => { type: ::Thrift::Types::I32, name: "employeeCount" },
    FOUNDERS => { type: ::Thrift::Types::LIST, name: "founders",
element: { type: ::Thrift::Types::STRUCT, class: ::Person } }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Job
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  COMPANY = 1
  DESIGNATION = 2
  STARTDATE = 3
  ENDDATE = 4
  ADDRESS = 5

  FIELDS = {
    COMPANY => { type: ::Thrift::Types::STRUCT, name: "company", class: ::Company },
    DESIGNATION => { type: ::Thrift::Types::STRING, name: "designation" },
    STARTDATE => { type: ::Thrift::Types::STRING, name: "startDate" },
    ENDDATE => { type: ::Thrift::Types::STRING, name: "endDate" },
    ADDRESS => { type: ::Thrift::Types::STRUCT, name: "address", class: ::Address }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Institute
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  NAME = 1
  ADDRESS = 2
  ESTABLISHDATE = 3
  STUDENTCOUNT = 4
  DIRECTOR = 5

  FIELDS = {
    NAME => { type: ::Thrift::Types::STRING, name: "name" },
    ADDRESS => { type: ::Thrift::Types::STRUCT, name: "address", class: ::Address },
    ESTABLISHDATE => { type: ::Thrift::Types::STRING, name: "establishDate" },
    STUDENTCOUNT => { type: ::Thrift::Types::I32, name: "studentCount" },
    DIRECTOR => { type: ::Thrift::Types::STRING, name: "director" }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Education
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  INSTITUTE = 1
  STARTDATE = 2
  ENDDATE = 3
  MAJOR = 4
  DEGREE = 5
  GPA = 6

  FIELDS = {
    INSTITUTE => { type: ::Thrift::Types::STRUCT, name: "institute", class: ::Institute },
    STARTDATE => { type: ::Thrift::Types::STRING, name: "startDate" },
    ENDDATE => { type: ::Thrift::Types::STRING, name: "endDate" },
    MAJOR => { type: ::Thrift::Types::STRING, name: "major" },
    DEGREE => { type: ::Thrift::Types::STRING, name: "degree" },
    GPA => { type: ::Thrift::Types::DOUBLE, name: "gpa" }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Profile
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  USERID = 1
  PERSON = 2
  BIO = 3
  HOMETOWN = 4
  HOBBY = 5
  DOB = 6
  OCCUPATION = 7
  JOBS = 8
  EDUCATIONS = 9

  FIELDS = {
    USERID => { type: ::Thrift::Types::I32, name: "userId" },
    PERSON => { type: ::Thrift::Types::STRUCT, name: "person", class: ::Person },
    BIO => { type: ::Thrift::Types::STRING, name: "bio" },
    HOMETOWN => { type: ::Thrift::Types::STRUCT, name: "hometown", class: ::Address },
    HOBBY => { type: ::Thrift::Types::STRING, name: "hobby" },
    DOB => { type: ::Thrift::Types::STRING, name: "dob" },
    OCCUPATION => { type: ::Thrift::Types::STRING, name: "occupation" },
    JOBS => { type: ::Thrift::Types::LIST, name: "jobs",
element: { type: ::Thrift::Types::STRUCT, class: ::Job } },
    EDUCATIONS => { type: ::Thrift::Types::LIST, name: "educations",
element: { type: ::Thrift::Types::STRUCT, class: ::Education } }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Tweet
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  PROFILE = 1
  TEXT = 2
  LOC = 3
  TWEETTYPE = 4
  LANGUAGE = 5

  FIELDS = {
    PROFILE => { type: ::Thrift::Types::STRUCT, name: "profile", class: ::Profile },
    TEXT => { type: ::Thrift::Types::STRING, name: "text" },
    LOC => { type: ::Thrift::Types::STRUCT, name: "loc", class: ::Location },
    TWEETTYPE => { type: ::Thrift::Types::I32, name: "tweetType", default: 0, enum_class: ::TweetType },
    LANGUAGE => { type: ::Thrift::Types::STRING, name: "language", default: "english" }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
    return if @tweetType.nil? || ::TweetType::VALID_VALUES.include?(@tweetType)
    raise ::Thrift::ProtocolException.new(::Thrift::ProtocolException::UNKNOWN, "Invalid value of field tweetType!")
  end

  ::Thrift::Struct.generate_accessors self
end

class Timeline
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  PROFILETWEETS = 1
  FOLLOWERTWEETS = 2
  FOLLOWEETWEETS = 3

  FIELDS = {
    PROFILETWEETS => { type: ::Thrift::Types::LIST, name: "profileTweets",
element: { type: ::Thrift::Types::STRUCT, class: ::Tweet } },
    FOLLOWERTWEETS => { type: ::Thrift::Types::LIST, name: "followerTweets",
element: { type: ::Thrift::Types::STRUCT, class: ::Tweet } },
    FOLLOWEETWEETS => { type: ::Thrift::Types::LIST, name: "followeeTweets",
element: { type: ::Thrift::Types::STRUCT, class: ::Tweet } }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class HomePage
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  PROFILE = 1
  PROFILETWEETS = 2

  FIELDS = {
    PROFILE => { type: ::Thrift::Types::STRUCT, name: "profile", class: ::Profile },
    PROFILETWEETS => { type: ::Thrift::Types::LIST, name: "profileTweets",
element: { type: ::Thrift::Types::STRUCT, class: ::Tweet } }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Space
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  PROFILE = 1
  HOMEPAGE = 2
  TIMELINE = 3
  FOLLOWERS = 4
  FOLLOWEES = 5

  FIELDS = {
    PROFILE => { type: ::Thrift::Types::STRUCT, name: "profile", class: ::Profile },
    HOMEPAGE => { type: ::Thrift::Types::STRUCT, name: "homePage", class: ::HomePage },
    TIMELINE => { type: ::Thrift::Types::STRUCT, name: "timeline", class: ::Timeline },
    FOLLOWERS => { type: ::Thrift::Types::LIST, name: "followers",
element: { type: ::Thrift::Types::STRUCT, class: ::Profile } },
    FOLLOWEES => { type: ::Thrift::Types::LIST, name: "followees",
element: { type: ::Thrift::Types::STRUCT, class: ::Profile } }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end

class Twitter
  include ::Thrift::Struct_Union
  include ::Thrift::Struct
  SPACES = 1

  FIELDS = {
    SPACES => { type: ::Thrift::Types::LIST, name: "spaces",
element: { type: ::Thrift::Types::STRUCT, class: ::Space } }
  }.freeze

  def struct_fields
    FIELDS
  end

  def validate
  end

  ::Thrift::Struct.generate_accessors self
end
