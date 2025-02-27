# ETL Pipeline Project

## Project Description
The goal of the project is to build an ETL pipeline. ETL (Extract, Transform, Load) is a data pipeline used to collect data from various sources, transform the data according to business requirements, and load the data into a destination data storage.

This project contains the following files:
- `src/extract.py` - A Python script that contains instructions to connect to Amazon Redshift data warehouse and to extract online transactions data with transformation tasks performed using SQL
- `src/transform.py` - A Python script that contains instructions to identify and remove duplicated records
- `src/load_data_to_s3.py` - A Python script that contains instructions to connect to Amazon S3 cloud object storage and to write the cleaned data as a CSV file into an S3 bucket
- `main.py` - A Python script that contains all instructions to execute all the steps to extract, transform, and load the transformed data using the functions from extract.py, transform.py, and load_data_to_s3.py
- `.env.example` - A text document that contains the list of environment variables used in .env file
- `requirements.txt` - A text document that contains all the libraries required to execute the code
- `.gitignore` - A text document that specifies intentionally untracked files that Git should ignore

## How to Run the ETL Pipeline Project

### A. To run the ETL pipeline from Command Line Interface:

#### Requirements
- Python 3+
- Python IDE or Text Editor and Command Line Interface

#### Instructions
1. Copy the `.env.example` file to `.env` and fill out the environment variables
2. Install all the libraries needed to execute main.py
3. Run the main.py script
   - Windows:
     ```
     pip install -r requirements.txt
     python main.py
     ```
   - Mac/Linux:
     ```
     pip3 install -r requirements.txt
     python3 main.py
     ```



### B. Project Structure Details

#### Extract Module
The extract module (`src/extract.py`) connects to Amazon Redshift and extracts transaction data. It:
- Establishes a secure connection to Redshift using environment variables
- Executes SQL queries to extract and pre-transform data
- Returns a pandas DataFrame with the extracted data

#### Transform Module
The transform module (`src/transform.py`) processes the extracted data to:
- Identify and remove duplicate records
- Ensure data consistency
- Apply business rules and transformations
- Return a cleaned DataFrame ready for loading

#### Load Module
The load module (`src/load_data_to_s3.py`):
- Connects to Amazon S3 using environment credentials
- Writes the transformed data as a CSV file to the specified S3 bucket
- Includes error handling and logging functionality

#### Main Script
The `main.py` script orchestrates the ETL process by:
- Importing functions from all modules
- Running them in sequence
- Handling exceptions
- Providing execution status and logs

## Environment Variables
The following environment variables need to be set in your `.env` file:
- `REDSHIFT_HOST`: Redshift cluster endpoint
- `REDSHIFT_PORT`: Redshift port (typically 5439)
- `REDSHIFT_DATABASE`: Database name
- `REDSHIFT_USER`: Username for Redshift
- `REDSHIFT_PASSWORD`: Password for Redshift
- `AWS_ACCESS_KEY_ID`: AWS access key
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `S3_BUCKET_NAME`: Name of the S3 bucket for data storage
- `S3_FILE_PATH`: Path within the bucket to store the output file

## Troubleshooting
- If connection to Redshift fails, verify your network settings and VPC configuration
- For S3 access errors, check IAM permissions and credentials
- For dependency issues, ensure all required packages are installed via `requirements.txt`
