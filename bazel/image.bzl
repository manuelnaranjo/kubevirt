"""shared helper to provision users into distroless images

Create an OCI layer capable of provisioning a user into the target image
"""

load("@rules_distroless//distroless:defs.bzl", "flatten", "group", "home", "passwd")

def provision_user(name, username = None, groupname = None, uid = -1, gid = -1):
    """provision a user into the target image

    Args:
        name (str): name of the bazel target
        username (str): username of the user
        groupname (str): groupname of the user
        uid (int): uid of the user
        gid (int): gid of the user
    """

    home(
        name = "{}_home".format(name),
        dirs = [
            dict(
                home = "/home/{}".format(username),
                uid = uid,
                gid = gid,
            ),
        ],
        visibility = ["//visibility:private"],
    )

    passwd(
        name = "{}_passwd".format(name),
        entries = [
            dict(
                gecos = [username],
                gid = gid,
                home = "/home/{}".format(username),
                shell = "bin/bash",
                username = username,
                uid = uid,
            ),
        ],
        visibility = ["//visibility:private"],
    )

    group(
        name = "{}_group".format(name),
        entries = [
            dict(
                name = groupname,
                gid = gid,
                users = [
                    username,
                ],
            ),
        ],
        visibility = ["//visibility:private"],
    )

    flatten(
        name = name,
        tars = [
            "{}_home".format(name),
            "{}_passwd".format(name),
            "{}_group".format(name),
        ],
        deduplicate = True,
        visibility = ["//visibility:private"],
    )
