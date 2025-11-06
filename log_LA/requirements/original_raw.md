
GPT link: https://chatgpt.com/g/g-p-689be476300c81918ff64ace21c5d27a-abr/c/690addab-4698-8320-a6ed-80d8aa461daf

# Requirement for claude requirement

Good, I want you create a requirement doc for claude: 

* Concise, minimium, straigh to point, keep only important , core requirement, avoid verbose. 
* I Mainly want claude to build a solution demo, using my current azure logined session (az alreadyu login) 
* Demo solution should inlcude:
    * DCR (public) , which has the GELF like schema: I want timestamp instead of ts. and map it to DCR expected timestamp. and zip all stuff into col attributes 
Note:
* I prefer col name all lowercase (except Azurfe default one) 
* app log will using attribute col to store nested fields. key=value
* My own GELF version:
    * host
    * environment
    * message
    * timestamp
    * level (integer, syslog)

* Provision: MI, with enough access, to send DCR. 
* Privison required other infra: rg: `rg-la-dcr-demo`, log analytic workspace, and other dependency if DCR need; My core requirement is to have DCR so I can use app code to send log into it and verify

# Client verification

* Client using Python SDK, to assume MI, and able to send metric to DCR
* send a few log into it:
    * Valid log, flat, no extra col, just required, core col
    * Valid log: with attributes have nested kv pairs, will be sent to dynamic col of DCR
    * Invalid log: it has unrecognized col, so my understanding is will be drop. and I want to verify the metric showing log count got dropped. 

# Questions

These are just my Q: won't affect requirement 
* Does dynamic attribute col supported nested fields , I need nested a few more levels? i.e think key always string. but some value could be object? assume DCR will support? 


# Ignore below requirement

Ignore requirement in this section and below

## Auto pack DCR

* In corp, I want a more flexible DCR: it can auto map unknown fields in root level all into a dynamic attributes col. i.e If not core "GELF" fields, it will be converted automatically into attributes, "pack". 
* If required fields missed, make it align with default DCR behaviour, reject or accept all ok, explain to me the default behaviour if required "MY GELF" fields missing
