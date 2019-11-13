#
# SPDX-License-Identifier: Apache-2.0
#

import paramiko
import pytest
import time
import yaml

class Config:
    """ Loads the configuration from a yaml file """

    def load(self):
        try:
            with open('conf_files/nodes-config.yaml') as f:
                lines = f.read()
        except FileNotFoundError:
            print ("Cannot find configuration file")
            raise

        data = yaml.load(lines, Loader=yaml.BaseLoader)
        if not data:
            print ("No data loaded from config file")
            return

        self.username = data['username']
        self.password = data['password']
        self.systemcontroller = data['systemcontroller']
        self.subcloud_standard = data['subcloud_standard']


class SSHConnection:
    """ Execute commands through SSH. """
    def __init__(self, host, username, password):
        self.host = host
        self.username = username
        self.password = password
        self.ssh = paramiko.SSHClient()
        self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    def open(self):
        try:
            self.ssh.connect(self.host, username=self.username,
                             password=self.password)
        except paramiko.AuthenticationException:
            print ("Authentication failure with host {}".format(self.host))
            raise

    def close(self):
        self.ssh.close()

    def command(self, cmd, inputs=[], sudo=False):
        if sudo:
            cmd = "sudo -k -S -p '' {}".format(cmd)

        stdin, stdout, stderr = self.ssh.exec_command(cmd)
        if sudo:
            stdin.write(self.password + '\n')
            stdin.flush()

        if len(inputs) > 0:
            for i in inputs:
                stdin.flush()
                stdin.write(i + '\n')
                time.sleep(1)

        while not stdout.channel.exit_status_ready():
            continue


        out = stdout.readlines()
        err = stderr.readline()
        retcode = stdout.channel.recv_exit_status()
        return (out, err, retcode)


class TestDistCloud:

    def setup_class(self):
        self.config = Config()
        self.config.load()
        self.ssh_master_cloud = SSHConnection(self.config.systemcontroller,
                                              self.config.username,
                                              self.config.password)
        self.ssh_master_cloud.open()

        self.ssh_subcloud = SSHConnection(self.config.subcloud_standard,
                                          self.config.username,
                                          self.config.password)
        self.ssh_subcloud.open()

    def teardown_class(self):
        self.ssh_master_cloud.close()
        self.ssh_subcloud.close()

    def test_systemcontroller_alive(self):
        cmd = "cat /etc/build.info"
        out, err, retcode = self.ssh_master_cloud.command(cmd)
        assert retcode == 0

    def test_subcloud_alive(self):
        cmd = "cat /etc/build.info"
        out, err, retcode = self.ssh_subcloud.command(cmd)
        assert retcode == 0

    def test_dump_bootstrap_values(self):
        with open('conf_files/distcloud-bootstrap.yml', 'r') as f:
            content = f.read()
        cmd = "echo '{}' > /home/sysadmin/bootstrap-values.yml".format(content)
        out, err, retcode = self.ssh_master_cloud.command(cmd)
        assert retcode == 0

    def test_ip_route(self):
        cmd = "ip route add 10.10.54.0/24 via 10.10.53.1"
        out, err, retcode = self.ssh_master_cloud.command(cmd, sudo=True)
        assert retcode == 0
        cmd = "ping -c 3 10.10.54.1"
        out, err, retcode = self.ssh_master_cloud.command(cmd)
        assert retcode == 0

    def test_add_subcloud(self):
        source_cmd = "source /etc/platform/openrc"
        dc_cmd = "dcmanager subcloud add " \
        "--bootstrap-address 10.10.54.11 " \
        "--bootstrap-values bootstrap-values.yml"
        cmd = "{}; {}".format(source_cmd, dc_cmd)

        # We need to send the password twice to the dcmanager command
        inputs = ['St4rlingX*', 'St4rlingX*']
        out, err, retcode = self.ssh_master_cloud.command(cmd, inputs=inputs)
        assert retcode == 0

    def test_look_for_subcloud(self):
        cmd = "source /etc/platform/openrc; dcmanager subcloud list"
        out, err, retcode = self.ssh_master_cloud.command(cmd)
        assert retcode == 0
        assert "subcloud_standard" in "".join(out)

    def test_remove_ip_route(self):
        cmd = "ip route del 10.10.54.0/24 via 10.10.53.1"
        out, err, retcode = self.ssh_master_cloud.command(cmd, sudo=True)
        assert retcode == 0
