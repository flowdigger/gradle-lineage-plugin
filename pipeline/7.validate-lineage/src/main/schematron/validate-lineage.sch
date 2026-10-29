<?xml version="1.0" encoding="UTF-8"?>
<sch:schema xmlns:sch="http://purl.oclc.org/dsdl/schematron">
    <sch:pattern id="stitched-flow-required">
        <sch:rule context="stitched-flow">
            <sch:assert test="@id and normalize-space(@id) != ''">stitched-flow id required</sch:assert>
            <sch:assert test="@direct-flow-id and normalize-space(@direct-flow-id) != ''">stitched-flow direct-flow-id required</sch:assert>
            <sch:assert test="@source and normalize-space(@source) != ''">stitched-flow source required</sch:assert>
            <sch:assert test="@target and normalize-space(@target) != ''">stitched-flow target required</sch:assert>
            <sch:assert test="@operation and normalize-space(@operation) != ''">stitched-flow operation required</sch:assert>
            <sch:assert test="@resolution-status = ('PROVEN','DECLARED','APPROXIMATE','UNRESOLVED')">stitched-flow resolution-status invalid</sch:assert>
            <sch:assert test="exists(evidence/@ref[normalize-space(.) != ''])">stitched-flow evidence required</sch:assert>
        </sch:rule>
    </sch:pattern>

    <sch:pattern id="stitched-uniqueness">
        <sch:rule context="stitched-lineage">
            <sch:assert test="count(stitched-flows/stitched-flow/@id) = count(distinct-values(stitched-flows/stitched-flow/@id))">stitched-flow ids must be unique</sch:assert>
        </sch:rule>
    </sch:pattern>

</sch:schema>
