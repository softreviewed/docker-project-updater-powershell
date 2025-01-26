# docker-project-updater-powershell
A PowerShell 7.x script to automate updating Docker projects: fetches Git updates, backups, stops/rebuilds/starts containers. Optimized for ease of use and real-time output.
Docker Project Updater Script (PowerShell)
Visit my website - SoftReviewed.com

# Docker Project Updater Script (PowerShell)

[Visit my website - SoftReviewed.com](https://softreviewed.com/)

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![PowerShell 7.x Compatible](https://img.shields.io/badge/PowerShell-7.x-brightgreen.svg?logo=powershell)](https://learn.microsoft.com/en-us/powershell/)

**Automate your Docker project updates with this PowerShell 7.x script!**

This script simplifies the process of updating Docker-based projects hosted on platforms like GitHub. It automates several key steps, ensuring your projects are always up-to-date and backed up before any changes are applied.

## Features

*   **Automated Git Updates:** Fetches the latest code changes from your Git repository.
*   **Project Backup:** Creates a timestamped backup of your Docker Compose files and `.env` file before updating, with configurable backup retention.
*   **Intelligent Container Management:**
    *   Stops running Docker containers for the project (gracefully and forcefully if needed).
    *   Rebuilds Docker containers with `--no-cache --pull` to ensure fresh images.
    *   Starts the updated Docker containers.
*   **Real-time Output Streaming:** Provides detailed, color-coded, real-time output in the PowerShell terminal during updates, including Docker build progress.
*   **Docker Daemon Status Check:** Verifies if Docker is running before proceeding and prompts the user if Docker is not started.
*   **User-Friendly Interface:** Clear status messages, progress indicators, and prompts for user interaction when needed.
*   **Configuration Options:**
    *   `BackupRetention`:  Control the number of backups to keep.
    *   `TimeFormat`: Customize the timestamp format in output messages.
*   **PowerShell 7.x Optimized:**  Leverages modern PowerShell features for performance and clarity.

## Prerequisites

Before using this script, ensure you have the following installed:

*   **PowerShell 7.x or later:**  Download from [https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
*   **Docker Desktop or Docker Engine:** Ensure Docker is installed and running on your system.
*   **Git CLI:** Git command-line interface must be installed and accessible in your system's PATH.

## Usage Instructions

1.  **Download the Script:** Download the `Update-DockerProjects.ps1` PowerShell script file from this repository.
2.  **Modify Project Paths:** Open the script in a text editor (like VS Code or Notepad).  Locate the `$projectPaths` array near the end of the script and **modify the paths** to point to the root directories of your Docker projects on your local machine.

    ```powershell
    # Usage Example - Uncomment and modify the path to use
    $projectPaths = @(
        "C:\path\to\your\docker-project-1"  # <--- Replace with your actual project path
        "C:\path\to\your\docker-project-2"  # <--- Add more project paths as needed
    )
    ```
3.  **Run the Script:**
    *   Open PowerShell 7.x as an Administrator (if required for Docker commands in your environment).
    *   Navigate to the directory where you saved the `Update-DockerProjects.ps1` file using the `cd` command.
    *   Execute the script by typing: `.\Update-DockerProjects.ps1` and pressing Enter.
4.  **Follow Prompts:** The script will guide you through the update process, prompting for confirmation before rebuilding containers if no Git updates are found.

## Configuration

You can customize the script's behavior by modifying the `$script:config` hashtable at the beginning of the script:

```powershell
# Configuration
$script:config = @{
    BackupRetention = 2  # Number of backups to keep (default: 2)
    TimeFormat      = "dd-MM-yyyy hh:mm tt" # Timestamp format (default: "dd-MM-yyyy hh:mm tt")
}
```

*   **`BackupRetention`:**  Sets the number of backup directories to retain in the `backups` folder within each project directory. Older backups will be automatically deleted.
*   **`TimeFormat`:**  Defines the format used for timestamps in the script's output messages.  See [Get-Date -Format](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-date?view=powershell-7.4) for formatting options.

## Example Usage

To update all projects listed in `$projectPaths`, simply run:

```powershell
.\Update-DockerProjects.ps1
```

To test the script's configuration without performing actual updates (useful for initial setup):

```powershell
.\Update-DockerProjects.ps1 -TestConfig -ProjectPath "C:\path\to\your\docker-project-1"
```
Replace `"C:\path\to\your\docker-project-1"` with a valid project path from your `$projectPaths` list.

## Contributing

Contributions are welcome!  If you have suggestions, bug reports, or improvements, please feel free to:

1.  **Fork** the repository.
2.  Create a **new branch** for your feature or bug fix.
3.  Submit a **pull request** with your changes.

## Author

This script was created by [SoftReviewed](https://softreviewed.com/).

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.

---

**Enjoy automating your Docker project updates!**
