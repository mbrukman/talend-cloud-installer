VAGRANTFILE_API_VERSION = "2"
second_disk_name = "second_disk.vdi"
Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.provider "virtualbox" do |vb|

    unless File.exist?(second_disk_name)
      vb.customize ["createhd", "--filename", second_disk_name, "--size", 10 * 1024]
    end
    vb.customize ['storagectl', :id, '--name', 'SATA Controller', '--portcount', 2]
    vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 1, "--device", 0, "--type", "hdd", "--medium", second_disk_name]
  end
end
