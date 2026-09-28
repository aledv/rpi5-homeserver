# OpenVPN Container Usage Guide

Welcome to the usage guide for managing your OpenVPN container. This guide explains how to access an interactive shell and set a custom password for the administrative user `openvpn`.

## Prerequisites

- Ensure Docker is installed and running on your system.
- The OpenVPN container should already be up and running.

## Accessing the Container Shell

To get an interactive shell inside the OpenVPN container, execute the following command:

```bash
docker exec -it openvpn-as /bin/bash
```

- `docker exec`: Executes a command inside a running container.
- `-it`: Opens an interactive terminal session.
- `openvpn-as`: The name of the running OpenVPN container.
- `/bin/bash`: Launches a bash shell within the container.

## Setting the Administrative User Password

Once inside the container shell, you can set a custom password for the `openvpn` administrative user using the `sacli` command:

```bash
sacli --user "openvpn" --new_pass "<PASSWORD>" SetLocalPassword
```

### Explanation of the Command

- `sacli`: A command-line utility for managing OpenVPN Access Server.
- `--user "openvpn"`: Specifies the username for which the password will be set.
- `--new_pass "<PASSWORD>"`: Sets the new password for the specified user. Replace `<PASSWORD>` with your preferred secure password.
- `SetLocalPassword`: Executes the action to set the local password for the user.

## Security Note

- Always choose a strong password to secure your administrative account.
- Avoid using easily guessable passwords.
- Regularly update the administrative password to maintain security.

## Exiting the Container Shell

After completing your tasks, type `exit` to leave the container shell:

```bash
exit
```

## Troubleshooting

- If you encounter any issues accessing the container or setting the password, ensure the container is running and named correctly.
- Check the Docker logs for additional details:

```bash
docker logs openvpn-as
```

---

For more information, visit the official OpenVPN Access Server documentation or consult your system administrator.
