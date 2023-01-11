# test-data-generator

A tool to generate synthetic and twitter like realistic data for tests.

This uses thrift objects for constructing twitter like data. 
The files are generated and resides in `resource/gen-rb` folder.

The generator creates data for the given size in bytes, 
data type ( realistic or synthetic) and data pattern (repeated, semi-repeated or random).

## Run

### Generate data into file

- clone the folder
- `bundle install`
- `bundle exec ruby ./data_generator.rb <filename> <data_type> <data_pattern> <data_size>`

### Filename

- Name of the file to which the generated data has to be written.

#### Data Types

- realistic
- synthetic

#### Data Patterns

- repeated
- semi_repeated
- random

#### Data Size

- Size of data to be generated in bytes.

#### Example

`bundle exec ruby ./data_generator.rb "test.txt" "realistic" "semi_repeated" "2000"`

