CfhighlanderTemplate do
  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'Ami', type: 'AWS::EC2::Image::Id'
    ComponentParam 'EnableScaling', 'false', allowedValues: ['true','false']
    ComponentParam 'SpotPrice', ''
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    
    MappingParam('InstanceType') do
      map 'EnvironmentType'
      attribute 'EcsInstanceType'
    end
    MappingParam('AsgMin') do
      map 'EnvironmentType'
      attribute 'EcsAsgMin'
    end
    MappingParam('AsgMax') do
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
    end

    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'SecurityGroupLoadBalancer', type: 'AWS::EC2::SecurityGroup::Id'
    ComponentParam 'SecurityGroupBastion', type: 'AWS::EC2::SecurityGroup::Id'
    ComponentParam 'FileSystem' if enable_efs

  end
end
