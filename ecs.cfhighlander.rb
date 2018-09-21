CfhighlanderTemplate do
  DependsOn stdext
  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'Ami', type: 'AWS::EC2::Image::Id'
    MappingParam('InstanceType', 't2.medium') do
      map 'EnvironmentType'
      attribute 'EcsInstanceType'
    end
    MappingParam('AsgMin', 1) do
      map 'EnvironmentType'
      attribute 'EcsAsgMin'
    end
    MappingParam('AsgMax', 1) do
      map 'EnvironmentType'
      attribute 'EcsAsgMax'
    end
    MappingParam('KeyName') do
      map 'AccountId'
      attribute 'KeyName'
    end
    MappingParam('DnsDomain') do
      map 'AccountId'
      attribute 'DnsDomain'
    end

    maximum_availability_zones.times do |az|
      ComponentParam "SubnetCompute#{az}"
      MappingParam "Az#{az}" do
        map 'AzMappings'
        attribute "Az#{az}"
      end
    end

    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'SecurityGroupLoadBalancer', type: 'AWS::EC2::SecurityGroup::Id'
    ComponentParam 'SecurityGroupBastion', type: 'AWS::EC2::SecurityGroup::Id'
    ComponentParam 'FileSystem' if enable_efs

  end
end
