# MySQL Server Backup Tool

This is a simple backup script for MySQL servers, designed to help you easily back up your databases and manage your backup files. You can specify your database connection details and customize the backup settings using environment variables. This tool also provides the option to clean up old backups to save space.

## Prerequisites

Before you can use this tool, make sure you have the following prerequisites installed on your system:

- **MySQL Client**: Ensure that you have the MySQL client installed to interact with your MySQL databases.

## Setup

1. Clone this repository to your local machine or server.

   ```bash
   git clone https://github.com/obrunsmann/mysql-server-backup.git
   cd mysql-server-backup
   ```

2. Create a `.env` file based on the `.env.example` template provided. This file will hold your database connection details and backup configuration.

   ```bash
   cp .env.example .env
   ```

3. Open the `.env` file in a text editor and provide the required information:

   - `db_host`: The hostname or IP address of your MySQL server.
   - `db_user`: The MySQL user with backup privileges.
   - `db_pass`: The password for the MySQL user.
   - `max_parallel`: The maximum number of parallel database backups.
   - `max_backups`: The maximum number of backup sets to retain.

4. Make sure the script file is executable.

   ```bash
   chmod +x backup.sh
   ```

## Usage

To create database backups using this tool, simply run the `backup.sh` script:

```bash
./backup.sh
```

The script will perform the following actions:

1. **Load Environment Variables**: It reads the configuration from the `.env` file.

2. **Create Backup Directory**: It creates a directory in the `backup/` folder with a timestamp to store the backups.

3. **Backup Databases in Parallel**: It retrieves a list of databases from the MySQL server (excluding system databases) and backs them up in parallel based on the `max_parallel` setting.

4. **Cleanup Old Backups**: It checks the number of backup sets and removes old backups if the number exceeds the `max_backups` setting.

## Example

Here's an example of how to run the backup script:

```bash
./backup.sh
```

## License

This backup tool is released under the MIT License. See the [LICENSE](LICENSE) file for more details.

## Author

- **Oliver Brunsmann**: [@obrunsmann](https://github.com/obrunsmann)

---

That's it! You now have a simple backup tool to help you manage your MySQL database backups. If you encounter any issues or have suggestions for improvements, feel free to open an issue on GitHub or contribute to the project.