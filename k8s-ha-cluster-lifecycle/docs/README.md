# Execution walkthroughs

Three documents explain, start to end, what happens when each project runs:

| Document | Covers |
|---|---|
| [Phase 2 Terraform: Execution from Start to End](https://claude.ai/code/artifact/09b1e07e-d837-49ed-ba82-b9c2dfadac2f) | bootstrap → init → plan → apply (resource order, module by module) → hand-off to Ansible → later runs → destroy |
| [Phase 2 Ansible: Execution from Start to End](https://claude.ai/code/artifact/b5dc8caa-de8e-4e8f-b620-b9cfe7325b26) | one-time setup, config/vault/dynamic inventory loading, every play and role in order, secret flow, data between plays |
| [Phase 3 Terraform (EKS): Execution from Start to End](https://claude.ai/code/artifact/041c086e-dd9c-4e0c-a905-f611eff830ac) | bootstrap, stack 10-infra (VPC + EKS internals), stack 20-platform (secrets, Pod Identity, Helm), deploy, destroy order |

Each document can be exported to Markdown, PDF or Word from its page.
