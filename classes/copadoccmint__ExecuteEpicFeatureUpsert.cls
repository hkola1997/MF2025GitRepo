global class ExecuteEpicFeatureUpsert extends VSTSIntegrationConstants implements Database.Batchable<List<String>>,Database.AllowsCallouts,Database.Stateful {
    private String pid;
    private String projectExtId;
    private String workspaceId;
    private String teamInfo;
    private String namedCredential;
    private copado__Project__c project;
    private Boolean isSprint;
    private Boolean isEpic;
    private Boolean isFeature;
    
    public List<Map<String, String>> userStoryList {
        get {
            if (null == userStoryList) {
                userStoryList = new List<Map<String, String>>();
            }
            return userStoryList;
        }
        set;
    }
    public List<List<String>> wIIds {
        get {
            if (null == wIIds) {
                wIIds = new List<List<String>>{new List<String>()};
            }
            return wIIds;
        }
        set;
    }
    global ExecuteEpicFeatureUpsert(copado__Project__c project, Boolean isEpic) {
        this.project = project;
        this.isEpic = isEpic;
        pid = project.id;
        projectExtId = project.Project_External_Id__c;
        workspaceId = isEpic ? project.Epic_Query__c : project.Feature_Query__c;
        namedCredential = project.Copado_Integration_Setting__r.Named_Credential__c;
        teamInfo = null != project.Team_Info__c ? project.Team_Info__c : EMPTY_CHAR;
    }
    
    global Iterable<List<String>> start(Database.BatchableContext bc) {
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
        authWrapper authWrapperItem = (authWrapper) parser.readValueAs(authWrapper.class);
        if((currentIndex != 0 || (currentIndex == 0 && wIIds[0].size() != 0)) && authWrapperItem.workItems.size() > 0){
            currentIndex++;
            wIIds.add(new List<String>());
        }
        Integer counter4Ids = 0;
        for (workItemsWrapper wiw : authWrapperItem.workItems) {
            wIIds[currentIndex].add(String.valueOf(wiw.id));
            counter4Ids++;
            if (counter4Ids == vstsPaginationSize) {
                wIIds.add(new List<String>());
                counter4Ids = 0;
                currentIndex++;
            }
        }
        return wIIds;
    }

    global void execute(Database.BatchableContext BC, List<List<String>> scope) {
        List<copado__Epic__c> epics = new List<copado__Epic__c>();
        List<copado__Application_Feature__c> features = new List<copado__Application_Feature__c>();
        List<List<String>> currentWiIds = scope;
        String ids = '';
        for(Integer i = 0; i < currentWiIds.size(); i++){
            ids += String.join(currentWiIds[i], COMMA) + COMMA;
        }
        ids = ids.subString(0, ids.length() - 1);
        if(currentWiIds.size() != 0){
            //callout to have all fields for desired workItems
            String responseText = CopadoCCMutilities.MakeCallout(
                namedCredential,
                projectExtId,
                ids,
                workspacePath,
                '', //FIELD_QUERY_PATH + fieldsToFetch,
                new List<string>{ CONTENT_TYPE_HEADER, CONNECTION_HEADER },
                Method.GET,
                null,
                null,
                project
            );

            Map<String, Object> results;
            try {
                results = (Map<String, Object>) JSON.deserializeUntyped(responseText);
                List<Object> values = (List<Object>) results.get(VALUE_KEYWORD);
                for (Object value : values) {
                    Map<String, Object> currentValue = (Map<String, Object>) value;
                    if (null != currentValue.get(FIELDS_STRING)) {
                        Map<String, Object> fields = (Map<String, Object>) currentValue.get(FIELDS_STRING);
                        if(isEpic){
                            epics.add(
                                new copado__Epic__c(
                                    External_Id__c = String.valueOf(currentValue.get(ID_KEYWORD)),
                                    copado__Epic_Title__c = String.valueOf(fields.get('System.Title')).left(80),
                                    copado__Description__c = String.valueOf(fields.get('System.Description'))
                                )
                            );
                        } else {
                            features.add(
                                new copado__Application_Feature__c(
                                    External_Id__c = String.valueOf(currentValue.get(ID_KEYWORD)),
                                    Name = String.valueOf(fields.get('System.Title')).left(80),
                                    copado__Description__c = String.valueOf(fields.get('System.Description'))
                                )
                            );
                        }
                    }
                }    
                if(isEpic){
                    upsert epics External_Id__c;
                } else {
                    upsert features External_Id__c;
                }
            } catch (Exception ex) {
                if(null != results) {
                    System.debug('Conversion Error for ==> ' + results.get(VALUE_KEYWORD));
                }
                System.debug('Error message ==> ' + ex.getMessage());
            }
        }
        CopadoCCMutilities.createLogRecords();
    }

    global void finish(Database.BatchableContext BC) {
        if(isEpic){
            database.executeBatch(new ExecuteEpicFeatureUpsert(project, false),1);
        } else {
            database.executeBatch(new ExecuteParentHierarchy(project));
        }
    }
}