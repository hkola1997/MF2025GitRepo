global class ExecuteParentHierarchy extends VSTSIntegrationConstants implements Database.Batchable<List<WorkItemRelations>>,Database.AllowsCallouts{
    private String pid;
    private String projectExtId;
    private String workspaceId;
    private String teamInfo;
    private String namedCredential;
    private copado__Project__c project;
    private Map<String, copado__Epic__c> epicsByExId = new Map<String, copado__Epic__c>();
    private Map<String, copado__Application_Feature__c> featuresByExId = new Map<String, copado__Application_Feature__c>();
    private Map<String, copado__User_Story__c> storiesByExId = new Map<String, copado__User_Story__c>();
    
    public List<Map<String, String>> userStories {
        get {
            if (null == userStories) {
                userStories = new List<Map<String, String>>();
            }
            return userStories;
        }
        set;
    }
    public List<Map<String, String>> epics {
        get {
            if (null == epics) {
                epics = new List<Map<String, String>>();
            }
            return epics;
        }
        set;
    }
    public List<Map<String, String>> features {
        get {
            if (null == features) {
                features = new List<Map<String, String>>();
            }
            return features;
        }
        set;
    }
    public List<List<WorkItemRelations>> wIIds {
        get {
            if (null == wIIds) {
                wIIds = new List<List<WorkItemRelations>>{new List<WorkItemRelations>()};
            }
            return wIIds;
        }
        set;
    }
    global ExecuteParentHierarchy(copado__Project__c project) {
        pid = project.id;
        projectExtId = project.Project_External_Id__c;
        workspaceId = project.Tree_of_Work_Items_Query__c;
        namedCredential = project.Copado_Integration_Setting__r.Named_Credential__c;
        teamInfo = null != project.Team_Info__c ? project.Team_Info__c : EMPTY_CHAR;
    }
    
    global Iterable<List<WorkItemRelations>> start(Database.BatchableContext bc) {
        // collect the batches of records or objects to be passed to execute
        Integer currentIndex = 0;
        //callout to find ids of the WorkItems exist on VSTS
        String responseText = CopadoCCMutilities.MakeCallout(
            namedCredential,
            projectExtId,
            workspaceId,
            authQueryPath,
            authApiVersion,
            new List<String>{ CONTENT_TYPE_HEADER },
            Method.GET,
            null,
            null,
            project
        );
        JSONParser parser = JSON.createParser(responseText);
        //wrapper class direct parse
        hierarchyWrapper hierarchyWrapperItem = (hierarchyWrapper) parser.readValueAs(hierarchyWrapper.class);
        if((currentIndex != 0 || (currentIndex == 0 && wIIds[0].size() != 0)) && hierarchyWrapperItem.workItemRelations.size() > 0){
            currentIndex++;
            wIIds.add(new List<WorkItemRelations>());
        }
        Integer counter4Ids = 0;
        for (WorkItemRelations wiw : hierarchyWrapperItem.workItemRelations) {
            wIIds[currentIndex].add(wiw);
            counter4Ids++;
            if (counter4Ids == vstsPaginationSize) {
                wIIds.add(new List<WorkItemRelations>());
                counter4Ids = 0;
                currentIndex++;
            }
        }
        return wIIds;
    }

    global void execute(Database.BatchableContext BC, List<List<WorkItemRelations>> scope) {
        Set<String> parentIds = new Set<String>();
        Set<String> childIds = new Set<String>();
        List<List<WorkItemRelations>> currentWiIds = scope;
        for(List<WorkItemRelations> relations : currentWiIds){
            for(WorkItemRelations relation : relations){
                if(null != relation.target){
                    childIds.add(String.valueOf(relation.target.id));
                }
                if(null != relation.source){
                    parentIds.add(String.valueOf(relation.source.id));
                }
            }
        }
        
        List<copado__Epic__c> epics = [SELECT Id, External_Id__c FROM copado__Epic__c WHERE External_Id__c IN : parentIds];
        for(copado__Epic__c epic : epics){
            epicsByExId.put(epic.External_Id__c, epic);
        }
        
        List<copado__Application_Feature__c> features = [SELECT Id, External_Id__c, copado__Epic__c FROM copado__Application_Feature__c WHERE External_Id__c IN : parentIds OR External_Id__c IN : childIds];
        for(copado__Application_Feature__c feature : features){
            featuresByExId.put(feature.External_Id__c, feature);
        }
        
        List<copado__User_Story__c> stories = [SELECT Id, copado__Epic__c, copado__US_Feature__c, External_Id__c FROM copado__User_Story__c WHERE External_Id__c IN : childIds];
        for(copado__User_Story__c story : stories){
            storiesByExId.put(story.External_Id__c, story);
        }
        
        for(List<WorkItemRelations> relations : currentWiIds){
            for(WorkItemRelations relation : relations){
                SObject epic, feature;
                if(null != relation.source){
                    if(epicsByExId.containsKey(String.valueOf(relation.source.Id))){
                        epic = epicsByExId.get(String.valueOf(relation.source.Id));
                    } else if(featuresByExId.containsKey(String.valueOf(relation.source.Id))){
                        feature = featuresByExId.get(String.valueOf(relation.source.Id));
                    } 
                }
                if(null != relation.target){
                    if(feature != null && featuresByExId.containsKey(String.valueOf(relation.target.Id))){
                        featuresByExId.get(String.valueOf(relation.target.Id)).copado__Epic__c = (String)feature.get('copado__Epic__c');
                        featuresByExId.get(String.valueOf(relation.target.Id)).copado__Parent_Feature__c = feature.Id;
                    } else if(feature != null && storiesByExId.containsKey(String.valueOf(relation.target.Id))){
                        storiesByExId.get(String.valueOf(relation.target.Id)).copado__US_Feature__c = feature.Id;
                        storiesByExId.get(String.valueOf(relation.target.Id)).copado__Epic__c = (String)feature.get('copado__Epic__c');
                    } else if(epic != null && featuresByExId.containsKey(String.valueOf(relation.target.Id))){
                        featuresByExId.get(String.valueOf(relation.target.Id)).copado__Epic__c = epic.Id;
                    } else if(epic != null && storiesByExId.containsKey(String.valueOf(relation.target.Id))){
                        storiesByExId.get(String.valueOf(relation.target.Id)).copado__Epic__c = epic.Id;
                    } 
                }
            }
        }
        Database.update(featuresByExId.values(), false);
        Database.update(storiesByExId.values(), false);
    }

    global void finish(Database.BatchableContext BC) {
        
    }
}