<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                xmlns:lin="urn:uniform-lineage"
                exclude-result-prefixes="lin">
    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:template match="/stitched-lineage">
        <rdf:RDF>
            <xsl:for-each select="stitched-flows/stitched-flow">
                <xsl:sort select="@id"/>
                <rdf:Description rdf:about="{concat('urn:lineage:flow:', @id)}">
                    <lin:source><xsl:value-of select="@source"/></lin:source>
                    <lin:target><xsl:value-of select="@target"/></lin:target>
                    <lin:operation><xsl:value-of select="@operation"/></lin:operation>
                    <lin:resolutionStatus><xsl:value-of select="@resolution-status"/></lin:resolutionStatus>
                </rdf:Description>
            </xsl:for-each>
        </rdf:RDF>
    </xsl:template>
</xsl:stylesheet>
