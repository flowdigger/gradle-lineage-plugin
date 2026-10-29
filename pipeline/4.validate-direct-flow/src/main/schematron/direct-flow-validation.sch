<?xml version="1.0" encoding="UTF-8"?>
<sch:schema xmlns:sch="http://purl.oclc.org/dsdl/schematron">
    <sch:pattern id="direct-flow-required-fields">
        <sch:rule context="direct-flow">
            <sch:assert test="@id and normalize-space(@id) != ''">direct-flow id required</sch:assert>
            <sch:assert test="@source and normalize-space(@source) != ''">direct-flow source required</sch:assert>
            <sch:assert test="@target and normalize-space(@target) != ''">direct-flow target required</sch:assert>
            <sch:assert test="@operation and normalize-space(@operation) != ''">direct-flow operation required</sch:assert>
            <sch:assert test="@derivation-rule and normalize-space(@derivation-rule) != ''">direct-flow derivation-rule required</sch:assert>
            <sch:assert test="@resolution-status = ('PROVEN','DECLARED','APPROXIMATE','UNRESOLVED')">direct-flow resolution-status invalid</sch:assert>
            <sch:assert test="exists(evidence/@ref[normalize-space(.) != ''])">direct-flow evidence ref required</sch:assert>
        </sch:rule>
    </sch:pattern>

    <sch:pattern id="java-direct-flow-evidence-unique">
        <sch:rule context="direct-flow[starts-with(@derivation-rule, 'java.')]">
            <sch:assert test="count(evidence/@ref) = count(distinct-values(evidence/@ref))">java direct-flow evidence refs must be unique per direct-flow</sch:assert>
        </sch:rule>
    </sch:pattern>

    <sch:pattern id="direct-flow-unique-ids">
        <sch:rule context="direct-flows-catalog">
            <sch:assert test="count(direct-flow/@id) = count(distinct-values(direct-flow/@id))">direct-flow ids must be unique</sch:assert>
        </sch:rule>
    </sch:pattern>
</sch:schema>
