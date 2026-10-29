<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                exclude-result-prefixes="xs"
                expand-text="yes">

    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:param name="sql-uri" as="xs:string?" select="''"/>
    <xsl:param name="java-uri" as="xs:string?" select="''"/>

    <xsl:template match="/">
        <direct-flows-catalog>
            <xsl:variable name="all-flows" as="element(direct-flow)*"
                          select="(collection($sql-uri)/direct-flows/direct-flow,
                                   collection($java-uri)/direct-flows/direct-flow)"/>
            <xsl:for-each-group select="$all-flows" group-by="string(@id)">
                <xsl:sort select="current-grouping-key()"/>
                <xsl:copy-of select="current-group()[1]"/>
            </xsl:for-each-group>
        </direct-flows-catalog>
    </xsl:template>

</xsl:stylesheet>
