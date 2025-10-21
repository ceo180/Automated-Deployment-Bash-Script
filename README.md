Automated Deployment Script
Overview
A production-grade Bash script that automates the complete deployment lifecycle of Dockerized applications on remote Linux servers. This script handles everything from repository cloning to container deployment and Nginx reverse proxy configuration.
Features
✅ Comprehensive Input Validation - Validates URLs, IP addresses, ports, and file paths
✅ Error Handling - Robust error handling with meaningful exit codes
✅ Detailed Logging - Timestamped logs for debugging and audit trails
✅ Idempotent Operations - Safe to run multiple times without breaking existing setups
✅ Docker & Docker Compose Support - Works with both Dockerfile and docker-compose.yml
✅ Nginx Reverse Proxy - Automatic configuration for port 80 access
✅ SSH Connectivity Checks - Validates connection before deployment
✅ Cleanup Mode - Easy removal of deployed resources
✅ Color-Coded Output - Easy-to-read terminal output
Prerequisites
Local Machine

Bash 4.0 or higher
Git
SSH client
rsync

Remote Server

Linux-based OS (Ubuntu/Debian recommended)
SSH access with key-based authentication
Sudo privileges for the user
Open ports: 22 (SSH), 80 (HTTP), and your application port

Installation

Clone this repository:

bashgit clone https://github.com/yourusername/hng13-stage1-devops.git
cd hng13-stage1-devops

Make the script executable:

bashchmod +x deploy.sh
Usage
Standard Deployment
Run the script:
bash./deploy.sh
You'll be prompted for:

Git Repository URL
Personal Access Token (PAT)
Branch name (default: main)
SSH username
Server IP address
SSH key path (default: ~/.ssh/id_rsa)
Application port

Cleanup Mode
To remove all deployed resources:
bash./deploy.sh --cleanup
Script Workflow
1. Parameter Collection

Validates all user inputs
Ensures proper formatting of URLs, IPs, and ports
Securely handles Personal Access Token

2. Repository Management

Clones the Git repository using PAT authentication
Pulls latest changes if repository already exists
Switches to specified branch
Validates presence of Dockerfile or docker-compose.yml

3. SSH Connection

Tests SSH connectivity before deployment
Uses key-based authentication
Validates server accessibility

4. Remote Environment Setup

Updates system packages
Installs Docker and Docker Compose
Installs and configures Nginx
Adds user to Docker group
Verifies all installations

5. Application Deployment

Transfers project files via rsync
Stops and removes existing containers
Builds Docker image or runs docker-compose
Validates container health

6. Nginx Configuration

Creates reverse proxy configuration
Forwards port 80 to application port
Tests and reloads Nginx
Removes default Nginx site

7. Validation

Checks Docker service status
Verifies container is running
Tests Nginx status
Validates local and external endpoints

Log Files
Each deployment creates a timestamped log file:
deploy_YYYYMMDD_HHMMSS.log
Logs include:

All operations performed
Success/failure status
Error messages with exit codes
Timestamps for each action

Exit Codes
CodeDescription0Success1General error2Invalid PAT3Missing SSH username4Repository clone/pull failed5Navigation error6No Dockerfile or docker-compose.yml7SSH connection failed8Docker installation failed9Docker Compose installation failed10Nginx installation failed11File transfer failed12Docker Compose deployment failed13Docker image build failed14Container run failed15Container not running16Nginx config creation failed17Nginx config test failed18Nginx reload failed19Docker service not running20Container not found21Nginx not running
Example Deployment
bash$ ./deploy.sh

[INFO] ===== Parameter Collection =====
Enter Git Repository URL: https://github.com/username/my-app.git
Enter Personal Access Token (PAT): ****
Enter branch name (default: main): main
Enter SSH username: ubuntu
Enter server IP address: 13.60.27.34
Enter SSH key path (default: ~/.ssh/id_rsa): 
Enter application port: 3000

[SUCCESS] All parameters collected successfully
[INFO] ===== Repository Cloning =====
[INFO] Cloning repository...
[SUCCESS] Repository ready at: /tmp/tmp.abc123/my-app
...
[SUCCESS] Deployment Completed Successfully!
[SUCCESS] Application URL: http://13.60.27.34
Troubleshooting
SSH Connection Failed

Verify SSH key has correct permissions (chmod 600)
Ensure public key is in server's ~/.ssh/authorized_keys
Check if SSH port 22 is open on the server

Container Not Running

Check Docker logs: docker logs <container-name>
Verify Dockerfile has correct configuration
Ensure application port is correctly exposed

Nginx Configuration Failed

Verify Nginx syntax: sudo nginx -t
Check Nginx logs: sudo tail -f /var/log/nginx/error.log
Ensure no port conflicts

Application Not Accessible

Check security group/firewall rules
Verify port 80 is open
Test locally on server: curl localhost

Security Considerations

Never commit your Personal Access Token to version control
Use environment variables for sensitive data in production
Restrict SSH key permissions (chmod 600)
Use separate deployment keys with limited permissions
Regularly rotate access tokens and SSH keys

Idempotency
The script is designed to be idempotent:

Re-running won't duplicate resources
Existing containers are gracefully stopped before redeployment
Nginx configs are overwritten, not duplicated
No duplicate Docker networks created

Requirements
POSIX Compliance
This script follows POSIX standards and should work on:

Ubuntu/Debian
CentOS/RHEL
Amazon Linux
Other Linux distributions with Bash

Dependencies
All dependencies are automatically installed on the remote server:

Docker
Docker Compose
Nginx

Contributing
Contributions are welcome! Please:

Fork the repository
Create a feature branch
Test thoroughly
Submit a pull request

License
MIT License - feel free to use and modify for your needs.

Author
Emmanuel Oshike

Support
For issues or questions:

Check the log files first
Review the troubleshooting section
Open an issue on GitHub

Acknowledgments

HNG Internship Program
DevOps Track Mentors


Last Updated: October 2025
