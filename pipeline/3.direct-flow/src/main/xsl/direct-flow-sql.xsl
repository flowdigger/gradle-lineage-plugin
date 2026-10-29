<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:f="urn:uniform-direct-flow"
                exclude-result-prefixes="xs f"
                expand-text="yes">

    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:function name="f:norm" as="xs:string">
        <xsl:param name="v" as="xs:string?"/>
        <xsl:sequence select="normalize-space($v)"/>
    </xsl:function>

    <xsl:template match="/">
        <xsl:variable name="artifact" as="xs:string" select="string((/lineage/@source, base-uri(.))[1])"/>
        <direct-flows language="sql" artifact="{$artifact}">
            <xsl:for-each select="/lineage/procedure">
                <xsl:variable name="procedure" select="f:norm(@name)" as="xs:string"/>
                <xsl:for-each select="(insert|update|merge|delete)">
                    <xsl:variable name="op" as="xs:string" select="local-name()"/>
                    <xsl:variable name="target" as="xs:string" select="f:norm((to/@name)[1])"/>
                    <xsl:for-each select="from/@name[normalize-space(.) ne '' and normalize-space(.) ne 'dual']">
                        <xsl:variable name="source" as="xs:string" select="f:norm(.)"/>
                        <xsl:if test="$source ne '' and $target ne ''">
                            <direct-flow id="{concat('sql|', $procedure, '|', $op, '|', $source, '|', $target)}"
                                         source="{$source}"
                                         target="{$target}"
                                         operation="{$op}"
                                         derivation-rule="sql.statement.read-write"
                                         resolution-status="PROVEN"
                                         procedure="{$procedure}">
                                <evidence ref="{concat($artifact, '#', $procedure, '|', $op, '|', $source, '|', $target)}"/>
                            </direct-flow>
                        </xsl:if>
                    </xsl:for-each>
                </xsl:for-each>
            </xsl:for-each>
        </direct-flows>
    </xsl:template>

</xsl:stylesheet>
