HighlanderComponent do
  DependsOn 'vpc@1.0.4'
  Parameters do
    StackParam 'EnvironmentName', 'dev', isGlobal: true
    StackParam 'EnvironmentType', 'development', isGlobal: true
    StackParam 'Ami'
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
    subnet_parameters({'private'=>{'name'=>'Compute'}}, maximum_availability_zones)
    OutputParam component: 'vpc', name: "VPCId"
    OutputParam component: 'loadbalancer', name: 'SecurityGroupLoadBalancer'
    OutputParam component: 'bastion', name: 'SecurityGroupBastion'
  end
end
