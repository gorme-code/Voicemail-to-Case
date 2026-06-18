// Step 5 dedup-flow test: insert two Phone-origin Cases sharing one callback number.
Case a = new Case(Subject='Dedup test A', Origin='Phone', Status='New', Callback_Number__c='8035550199');
insert a;
Case b = new Case(Subject='Dedup test B', Origin='Phone', Status='New', Callback_Number__c='8035550199');
insert b;

Case aAfter = [SELECT Id, CaseNumber, Status FROM Case WHERE Id = :a.Id];
Case bAfter = [SELECT Id, CaseNumber, Status FROM Case WHERE Id = :b.Id];
List<CaseComment> onA = [SELECT CommentBody FROM CaseComment WHERE ParentId = :a.Id];
List<CaseComment> onB = [SELECT CommentBody FROM CaseComment WHERE ParentId = :b.Id];

System.debug('TESTOUT case_a=' + aAfter.CaseNumber + ' status=' + aAfter.Status + ' comments=' + onA.size());
System.debug('TESTOUT case_b=' + bAfter.CaseNumber + ' status=' + bAfter.Status + ' comments=' + onB.size());
for (CaseComment c : onB) { System.debug('TESTOUT b_comment_body=' + c.CommentBody); }
for (CaseComment c : onA) { System.debug('TESTOUT a_comment_body=' + c.CommentBody); }
