import os

from pytest import fixture, mark, skip

from keywords import kube_helper, system_helper, host_helper
from consts.filepaths import WRSROOT_HOME
from consts.cgcs import PodStatus, HostAvailState
from utils.tis_log import LOG
from utils.clients.ssh import ControllerClient

EDGEX_URL = 'https://github.com/rohitsardesai83/edgex-on-kubernetes/archive/master.zip'
EDGEX_ARCHIVE = 'master.zip'
EDGEX_HOME = 'edgex-on-kubernetes-master'
EDGEX_START = '/home/wrsroot/edgex-on-kubernetes-master/hack/edgex-up.sh'
EDGEX_STOP = '/home/wrsroot/edgex-on-kubernetes-master/hack/edgex-down.sh'


@fixture(scope='module')
def deploy_edgex(request):
    con_ssh = ControllerClient.get_active_controller()

    LOG.fixture_step("Downloading EdgeX-on-Kubernetes")
    con_ssh.exec_cmd('wget {}'.format(EDGEX_URL))
    charts_exist = con_ssh.file_exists(os.path.join(WRSROOT_HOME, EDGEX_ARCHIVE))
    assert charts_exist, '{} does not exist'.format(EDGEX_ARCHIVE)

    LOG.fixture_step("Extracting EdgeX-on-Kubernetes")
    con_ssh.exec_cmd('unzip {}'.format(os.path.join(WRSROOT_HOME, EDGEX_ARCHIVE)))

    LOG.fixture_step("Deploying EdgeX-on-Kubernetes")
    con_ssh.exec_cmd(EDGEX_START, 180)

    def delete_edgex():
        LOG.fixture_step("Destroying EdgeX-on-Kubernetes")
        con_ssh.exec_cmd(EDGEX_STOP, 180)

        LOG.fixture_step("Removing EdgeX-on-Kubernetes")
        con_ssh.exec_cmd('rm -rf {} {}'.format(os.path.join(WRSROOT_HOME, EDGEX_ARCHIVE),
                                               os.path.join(WRSROOT_HOME, EDGEX_HOME)))

    request.addfinalizer(delete_edgex)
    return


def check_host(controller):
    host = system_helper.get_active_controller_name()
    if controller == 'standby':
        controllers = system_helper.get_controllers(availability=(HostAvailState.AVAILABLE, HostAvailState.DEGRADED,
                                                                  HostAvailState.ONLINE))
        controllers.remove(host)
        if not controllers:
            skip('Standby controller does not exist or not in good state')
        host = controllers[0]
    return host


@mark.platform
@mark.parametrize('controller', [
    'active',
    'standby'
])
def test_kube_edgex_services(deploy_edgex, controller):
    """
    Test edgex pods are deployed and running
    Args:
        deploy_edgex (str): module fixture
        controller: test param
    Test Steps:
        - ssh to given controller
        - Wait for EdgeX pods deployment
        - Check all EdgeX pods are running
        - Check EdgeX services displayed: 'edgex-core-command', 'edgex-core-consul', 'edgex-core-data', 'edgex-core-metadata'
        - Check EdgeX deployments displayed: 'edgex-core-command', 'edgex-core-consul', 'edgex-core-data', 'edgex-core-metadata'

    """
    host = check_host(controller=controller)
    with host_helper.ssh_to_host(hostname=host) as con_ssh:

        pods = ('edgex-core-command', 'edgex-core-consul', 'edgex-core-data', 'edgex-core-metadata')
        LOG.tc_step("Check EdgeX pods on {} : {}".format(controller, pods))
        kube_system_info = kube_helper.get_pods_info(namespace='default', con_ssh=con_ssh,
                                                     type_names=('pod', 'service', 'deployment.apps'),
                                                     keep_type_prefix=False)

        for pod_info in kube_system_info['pod']:
            res, actual_pod_info = kube_helper.wait_for_pods(pod_info['name'], namespace='default', con_ssh=con_ssh)
            assert res, "Pod {} status is {} instead of {}". \
                format(actual_pod_info['name'], pod_info['status'], PodStatus.RUNNING)

        services = ('edgex-core-command', 'edgex-core-consul', 'edgex-core-data', 'edgex-core-metadata')
        LOG.tc_step("Check EdgeX services on {}: {}".format(controller, services))
        existing_services = kube_system_info['service']
        existing_services = [service['name'] for service in existing_services]
        for service in services:
            assert service in existing_services, "{} not in kube-system service table".format(service)

        deployments = ('edgex-core-command', 'edgex-core-consul', 'edgex-core-data', 'edgex-core-metadata')
        LOG.tc_step("Check kube-system deployments on {}: {}".format(controller, deployments))
        existing_deployments = kube_system_info['deployment.apps']
        existing_deployments = [deployment['name'] for deployment in existing_deployments]
        for deployment in deployments:
            assert deployment in existing_deployments, "{} not in kube-system deployment.apps table".format(deployment)
