$global:vms_home = "C:\Users\user\VirtualBox VMs"
$global:iso_root = "C:\Users\user\Downloads\iso\"
$global:vdi_root = "C:\Users\user\Downloads\vdi\"
$global:base_image = "$global:vdi_root\Ubuntu22_LTS_64.vdi"

#Install-Module -Name Posh-SSH -RequiredVersion 3.0.8
Set-PSDebug -Off

function create_basevm ($ostype) {
    # check ostype
    $supported_ostypes = vm_ostypes
    if ($ostype -notin $supported_ostypes){
        echo "Invalid ostype: $ostype! Please choose one of '$supported_ostypes'!"
        return
    }

    # all parameters
    $group_id = "/Linux" # must start with '/'
    $timestamp = get_timestamp
    $cpu_count = 2
    $memory_size = 4096
    $vram_size = 128
    $network_mode = "nat"
    $disk_size = 15 * 1024 # 15 GB
    $vm_name = "${ostype}_${timestamp}"
    $disk_medium_path = "${vms_home}/${group_id}/${vm_name}/${vm_name}.vdi"
    $disk_sc_name = "${vm_name}.disk_sc" # disk storage controller
    $dvd_sc_name = "${vm_name}.dvd_sc" # dvd storage controller
    $disk_sb_type = "sata" # system bus type
    $dvd_sb_type = "ide" # system bus type
    $disk_sc_type = "IntelAhci"
    $dvd_sc_type = "PIIX4"
    $sc_port_count = 2
    $disk_sc_attach_port = 0
    $dvd_sc_attach_port = 1
    $disk_sc_attach_device = 0
    $dvd_sc_attach_device = 0
    $disk_drive_type = "hdd"
    $dvd_drive_type = "dvddrive"

    $vrdeport = 10001

    # check available disk space
    $f_diskspace = get_free_disk_size
    $free_space_mb = [Math]::Round($f_diskspace, 0)
    if ($free_space_mb -lt $disk_size){
        echo "No enough free disk space! Required: $disk_size Mb, Available: $free_space_mb Mb"
        return
    }

    $iso_uri = ""
    switch ($ostype)
    {
        "ArchLinux_64" {
            $iso_uri="$iso_root/archlinux-2020.08.01-x86_64.iso"
        }
        "Fedora_64" {
            $iso_uri="$iso_root/Fedora-Workstation-Live-x86_64-32-1.6.iso"
        }
        "Ubuntu22_LTS_64"{
            $iso_uri="$iso_root/ubuntu-22.04.4-live-server-amd64.iso"
        }
    }

    echo "To create $vm_name as '$ostype' with '$iso_uri'"
    
    vbm createvm --name "${vm_name}" --groups "$group_id" --ostype "$ostype" --register --basefolder "$vms_home"
    vbm modifyvm "$vm_name" --cpus $cpu_count --memory $memory_size --vram $vram_size --nic1 $network_mode
    $ErrorActionPreference = "Continue"
    vbm createmedium disk --filename "$disk_medium_path" --size $disk_size
    $ErrorActionPreference = "Stop"

    # hardware disk
    vbm storagectl "$vm_name" --name "$disk_sc_name" --add $disk_sb_type --controller "$disk_sc_type" --portcount $sc_port_count --hostiocache off --bootable on
    vbm storageattach "$vm_name" --storagectl "$disk_sc_name" --port $disk_sc_attach_port --device $disk_sc_attach_device --type "$disk_drive_type" --medium "$disk_medium_path"
    
    # dvd
    vbm storagectl "$vm_name" --name "$dvd_sc_name" --add "$dvd_sb_type" --controller "$dvd_sc_type" --portcount $sc_port_count --bootable on --hostiocache off
    vbm storageattach "$vm_name" --storagectl "$dvd_sc_name" --port $dvd_sc_attach_port --device $dvd_sc_attach_device --type "$dvd_drive_type" --medium "$iso_uri"
    
    # boot from dvd before disk, after installation, we can change this
    vbm modifyvm "$vm_name" --boot1 dvd --boot2 disk --boot3 none --boot4 none

    vbm startvm "$vm_name"
}

function vm_ostypes(){
    $ostypes = @()
    vbm list ostypes | select-string -pattern '^ID:\s+(\w+)' | foreach-object {
        $ostypes += $_.matches[0].groups[1].value
    }
    return $ostypes
}

function get_free_disk_size () {
    $one_mb = 1024*1024;   
    $free_space = (get-psdrive C ).free/$one_mb;
    $free_space = [Math]::Round($free_space, 2)
    return $free_space
}

function get_timestamp(){
    Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
}


function create_vm ($vname, $vcpu, $vram, $vhdd) {

    $group_id = "/Linux" # must start with '/'
    $videoram_size = 128
    $network_mode = "natnetwork"
    $disk_medium_path = "${vms_home}/${group_id}/${vname}/${vname}.vdi"
    $disk_sc_name = "${vname}.disk_sc" # disk storage controller
    $disk_sc_attach_port = 0
    $disk_sb_type = "sata" # system bus type
    $disk_sc_attach_device = 0
    $sc_port_count = 2
    $disk_drive_type = "hdd"

    $f_diskspace = get_free_disk_size
    $free_space_mb = [Math]::Round($f_diskspace, 0)
    if ($free_space_mb -lt $vhdd){
        echo "No enough free disk space! Required: $disk_size Mb, Available: $free_space_mb Mb"
        return
    }

    Write-Host "To create $vname"
    vbm createvm --name "${vname}" --groups "$group_id" --ostype "Ubuntu22_LTS_64" --register --basefolder "$vms_home"
    vbm modifyvm "$vname" --cpus $vcpu --memory $vram --vram $videoram_size --nic1 $network_mode --nat-network1=Net1
    $ErrorActionPreference = "Continue"
    vbm clonemedium 4de4a32a-5fa2-4bd4-91ed-bc98c9504aa2 ${vms_home}/${vname}/${vname}.vdi
    $ErrorActionPreference = "Stop"
    #Copy-Item -Path ${base_image} ${disk_medium_path}
    Write-Host "Base file has been copied"
    Write-Host "${vname} ${disk_sc_name} ${disk_sb_type} ${sc_port_count}"
    vbm storagectl "${vname}" --name "${disk_sc_name}" --add "${disk_sb_type}" --controller IntelAHCI --portcount "${sc_port_count}" --hostiocache off --bootable on
    Write-Host "$vname" $disk_sc_name $disk_sc_attach_port  $disk_sc_attach_device $disk_drive_type $disk_medium_path
    vbm storageattach "$vname" --storagectl "$disk_sc_name" --port $disk_sc_attach_port --device $disk_sc_attach_device --type "$disk_drive_type" --medium ${vms_home}/${vname}/${vname}.vdi

}

function get_vm_ip($vname) {
    #echo "Waiting vm IP"
    $ErrorActionPreference = "Continue"
    $total = 60
    $count = $total

    while ($count -gt 0) {
 
        #echo "$count seconds remaining..."
        $vm_params = vbm guestproperty get "$vname" "/VirtualBox/GuestInfo/Net/0/V4/IP"
        if ($vm_params -ne 'No value set!') {
            break
        }
        Start-Sleep -Seconds 1
        $count--
 
    }
    $ErrorActionPreference = "Stop"
    $ip = (vbm guestproperty get "$vname" "/VirtualBox/GuestInfo/Net/0/V4/IP").Split(":")[1].TrimStart()
    return $ip
}

create_vm db 2 1024 15

vbm startvm db
Write-Host "VM has been started"

#$vm_ip = (vbm guestproperty get "$vname" "/VirtualBox/GuestInfo/Net/0/V4/IP").Split(":")[1].TrimStart()
$vm_ip = get_vm_ip $vname
vbm natnetwork modify --netname Net1 --port-forward-4 "ssh_db:tcp:[192.168.56.1]:1022:[$vm_ip]:22"


$Password = "123456"
$User = "user"
$ComputerName = "192.168.56.1"
$Port = 1022
$Command = "ls -la"

$secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
$Credentials = New-Object System.Management.Automation.PSCredential($User, $secpasswd)
$SessionID = New-SSHSession -ComputerName $ComputerName -Port $Port -Credential $Credentials #Connect Over SSH
Invoke-SSHCommand -Index $SessionID.Sessionid -Command $Command # Invoke Command Over SSH

Remove-SSHSession -Index 0 -Verbose
Invoke-SSHCommand -Index 0 -Command "uname -a"
#create_vm backend 1 1024 10
#create_vm web 1 1024 12
#vbm natnetwork modify --netname Net1 --port-forward-4 delete ssh_db
#vbm controlvm db poweroff