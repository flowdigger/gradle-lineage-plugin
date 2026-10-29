<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:map="http://www.w3.org/2005/xpath-functions/map"
                xmlns:f="urn:stitch-lineage"
                exclude-result-prefixes="xs map f">
    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:param name="table-index-uri" as="xs:string" select="''"/>

    <xsl:variable name="table-index-docs" as="document-node()*"
                  select="if (normalize-space($table-index-uri) ne '') then collection($table-index-uri) else ()"/>
    <xsl:variable name="table-name-to-schemas" as="map(xs:string, xs:string*)">
        <xsl:map>
            <xsl:for-each-group select="$table-index-docs//table[@name]" group-by="f:norm(@name)">
                <xsl:sort select="current-grouping-key()"/>
                <xsl:variable name="schemas" as="xs:string*"
                              select="sort(distinct-values(current-group()/ancestor::tables[1]/@schema ! normalize-space(.)[. ne '']))"/>
                <xsl:if test="current-grouping-key() ne '' and exists($schemas)">
                    <xsl:map-entry key="current-grouping-key()" select="$schemas"/>
                </xsl:if>
            </xsl:for-each-group>
        </xsl:map>
    </xsl:variable>

    <xsl:function name="f:norm" as="xs:string">
        <xsl:param name="value" as="xs:string?"/>
        <xsl:sequence select="lower-case(normalize-space($value))"/>
    </xsl:function>

    <xsl:function name="f:schemas-for-object" as="xs:string*">
        <xsl:param name="object-name" as="xs:string?"/>
        <xsl:variable name="key" as="xs:string" select="f:norm($object-name)"/>
        <xsl:sequence select="if ($key eq '' or not(map:contains($table-name-to-schemas, $key))) then () else $table-name-to-schemas($key)"/>
    </xsl:function>

    <xsl:function name="f:join-candidates" as="xs:string">
        <xsl:param name="values" as="xs:string*"/>
        <xsl:sequence select="string-join($values, '|')"/>
    </xsl:function>

    <xsl:function name="f:join-fqn-candidates" as="xs:string">
        <xsl:param name="object-name" as="xs:string?"/>
        <xsl:param name="schemas" as="xs:string*"/>
        <xsl:variable name="name" as="xs:string" select="normalize-space($object-name)"/>
        <xsl:sequence select="
            if ($name eq '' or empty($schemas)) then ''
            else string-join($schemas ! concat(., '.', $name), '|')
        "/>
    </xsl:function>

    <xsl:template match="/direct-flows-merged">
        <xsl:variable name="sorted-direct-flows" as="element(direct-flow)*">
            <xsl:for-each select="direct-flow">
                <xsl:sort select="@id"/>
                <xsl:sequence select="."/>
            </xsl:for-each>
        </xsl:variable>
        <xsl:variable name="flows-by-source" as="map(xs:string, element(direct-flow)*)">
            <xsl:map>
                <xsl:for-each-group select="$sorted-direct-flows[normalize-space(@source) ne '']" group-by="string(@source)">
                    <xsl:map-entry key="current-grouping-key()" select="current-group()"/>
                </xsl:for-each-group>
            </xsl:map>
        </xsl:variable>
        <stitched-lineage>
            <stitched-flows>
                <xsl:for-each select="$sorted-direct-flows">
                    <xsl:variable name="source-name" as="xs:string" select="normalize-space(@source)"/>
                    <xsl:variable name="target-name" as="xs:string" select="normalize-space(@target)"/>
                    <xsl:variable name="source-schemas" as="xs:string*" select="f:schemas-for-object($source-name)"/>
                    <xsl:variable name="target-schemas" as="xs:string*" select="f:schemas-for-object($target-name)"/>
                    <stitched-flow id="{concat('stitched|', @id)}"
                                   direct-flow-id="{@id}"
                                   source="{@source}"
                                   target="{@target}"
                                   source-schema-candidates="{f:join-candidates($source-schemas)}"
                                   target-schema-candidates="{f:join-candidates($target-schemas)}"
                                   source-fqn-candidates="{f:join-fqn-candidates($source-name, $source-schemas)}"
                                   target-fqn-candidates="{f:join-fqn-candidates($target-name, $target-schemas)}"
                                   operation="{@operation}"
                                   resolution-status="{@resolution-status}">
                        <xsl:copy-of select="evidence"/>
                    </stitched-flow>
                </xsl:for-each>
            </stitched-flows>
            <stitch-links>
                <xsl:for-each select="$sorted-direct-flows">
                    <xsl:variable name="left" select="."/>
                    <xsl:variable name="matches" as="element(direct-flow)*"
                                  select="if (normalize-space($left/@target) ne '' and map:contains($flows-by-source, string($left/@target)))
                                          then $flows-by-source(string($left/@target))
                                          else ()"/>
                    <xsl:for-each select="$matches">
                        <stitch-link from-direct-flow-id="{$left/@id}"
                                     to-direct-flow-id="{@id}"
                                     evidence-kind="fqn-or-schema-exact-match"
                                     evidence-value="{$left/@target}"/>
                    </xsl:for-each>
                </xsl:for-each>
            </stitch-links>
        </stitched-lineage>
    </xsl:template>
</xsl:stylesheet>
