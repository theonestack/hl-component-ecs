CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'Ami', type: 'AWS::EC2::Image::Id'
    ComponentParam 'EnableScaling', 'false', allowedValues: ['true','false']
    ComponentParam 'SpotPrice', ''

    ComponentParam 'InstanceType'
    ComponentParam 'AsgMin', '1'
    ComponentParam 'AsgMax', '2'
    ComponentParam 'KeyName', ''
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'

    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'SecurityGroupLoadBalancer', type: 'AWS::EC2::SecurityGroup::Id'
    ComponentParam 'SecurityGroupBastion', type: 'AWS::EC2::SecurityGroup::Id'
    ComponentParam 'FileSystem' if enable_efs

  end
end
